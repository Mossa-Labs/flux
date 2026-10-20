defmodule Flux.EmailAddress do
  @moduledoc """
  Strict validation for email addresses Flux will *send to or from*.

  Signup only needs to know an address is plausible enough to receive a link;
  an outbound sink needs more, because whatever passes here ends up in an SMTP
  envelope or a mail header. So this accepts the address shape a modern mail
  system actually delivers and rejects the rest, rather than everything
  RFC 5322 technically allows:

    * **Lengths** (RFC 5321 §4.5.3.1, RFC 1035): the whole address ≤ 254
      octets, local part ≤ 64, domain ≤ 253, each domain label ≤ 63.
    * **Local part**: a dot-atom of the WHATWG HTML "valid email address"
      characters — letters, digits and ``.!#$%&'*+/=?^_`{|}~-`` — with no
      leading, trailing or doubled dot. Quoted strings and comments are legal
      but obsolete, and a common injection vector, so they are rejected.
    * **Domain**: two or more letter/digit/hyphen labels, none starting or
      ending with a hyphen, and a TLD that is not all digits. Single-label hosts
      (`localhost`) and IP literals (`[1.2.3.4]`) are rejected.
    * **ASCII only**. Internationalized addresses (SMTPUTF8 / IDN) are refused
      with a message saying so, since many relays reject them and there is no
      IDNA conversion available here.

  Whitespace and control characters never pass, so a value cannot smuggle a
  CR/LF into a header. No DNS or MX lookup is made: validation runs on every
  form keystroke and must not depend on the network.
  """

  @max_address 254
  @max_local 64
  @max_domain 253
  @max_label 63

  # Ceiling on to + cc + bcc for one message — keeps a misconfigured sink from
  # becoming a bulk mailer, and sits under the API providers' own per-message caps.
  @max_recipients 50

  @local_part ~r/\A[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+(\.[A-Za-z0-9!#$%&'*+\/=?^_`{|}~-]+)*\z/
  @label ~r/\A[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\z/

  @doc "The most recipients a single message may carry across to, cc and bcc."
  @spec max_recipients() :: pos_integer()
  def max_recipients, do: @max_recipients

  @doc """
  Validates one address, returning it normalized: surrounding whitespace
  trimmed and the domain lower-cased. The local part keeps its case — RFC 5321
  leaves its interpretation to the receiving server.

      iex> Flux.EmailAddress.validate(" Ops@Example.COM ")
      {:ok, "Ops@example.com"}

      iex> Flux.EmailAddress.validate("ops@localhost")
      {:error, "domain must have at least two labels, like example.com"}
  """
  @spec validate(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(address) when is_binary(address) do
    address = String.trim(address)

    with :ok <- check_present(address),
         :ok <- check_ascii(address),
         :ok <- check_no_whitespace(address),
         {:ok, local, domain} <- split(address),
         :ok <- check_length(address, local, domain),
         :ok <- check_local(local),
         :ok <- check_domain(domain) do
      {:ok, local <> "@" <> String.downcase(domain)}
    end
  end

  def validate(_), do: {:error, "must be a string"}

  @doc """
  Validates a list of addresses — either a list or a single string separated by
  commas, semicolons or newlines. Blank entries are dropped and duplicates
  removed (case-insensitively), keeping the first spelling.

  Returns every normalized address, or one error per bad entry naming the
  address so the user can find it in a long list.
  """
  @spec validate_list(String.t() | [String.t()] | nil) ::
          {:ok, [String.t()]} | {:error, [String.t()]}
  def validate_list(nil), do: {:ok, []}
  def validate_list(value) when is_binary(value), do: value |> split_list() |> validate_list()

  def validate_list(addresses) when is_list(addresses) do
    {valid, errors} =
      addresses
      |> Enum.map(&if(is_binary(&1), do: String.trim(&1), else: &1))
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce({[], []}, fn address, {valid, errors} ->
        case validate(address) do
          {:ok, normalized} -> {[normalized | valid], errors}
          {:error, reason} -> {valid, [~s("#{display(address)}" #{reason}) | errors]}
        end
      end)

    case errors do
      [] -> {:ok, valid |> Enum.reverse() |> Enum.uniq_by(&String.downcase/1)}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_list(_), do: {:error, ["must be a list of email addresses"]}

  @doc """
  Splits a free-text recipient field (commas, semicolons or newlines) into
  trimmed, non-blank entries. Does not validate.
  """
  @spec split_list(String.t()) :: [String.t()]
  def split_list(value) when is_binary(value) do
    value
    |> String.split([",", ";", "\n", "\r"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp check_present(""), do: {:error, "can't be blank"}
  defp check_present(_), do: :ok

  defp check_ascii(address) do
    if address =~ ~r/\A[\x00-\x7F]*\z/ do
      :ok
    else
      {:error, "contains non-ASCII characters (internationalized addresses aren't supported yet)"}
    end
  end

  defp check_no_whitespace(address) do
    if address =~ ~r/[\s\x00-\x1F\x7F]/ do
      {:error, "must not contain spaces or control characters"}
    else
      :ok
    end
  end

  defp split(address) do
    case String.split(address, "@") do
      [local, domain] when local != "" and domain != "" -> {:ok, local, domain}
      [_, _] -> {:error, "must have text on both sides of the @"}
      [_] -> {:error, "must contain an @"}
      _ -> {:error, "must contain exactly one @"}
    end
  end

  defp check_length(address, local, domain) do
    cond do
      byte_size(address) > @max_address ->
        {:error, "must be at most #{@max_address} characters"}

      byte_size(local) > @max_local ->
        {:error, "part before the @ must be at most #{@max_local} characters"}

      byte_size(domain) > @max_domain ->
        {:error, "domain must be at most #{@max_domain} characters"}

      true ->
        :ok
    end
  end

  defp check_local(local) do
    cond do
      String.starts_with?(local, "\"") ->
        {:error, "quoted addresses aren't supported"}

      String.starts_with?(local, ".") or String.ends_with?(local, ".") ->
        {:error, "part before the @ must not start or end with a dot"}

      String.contains?(local, "..") ->
        {:error, "must not contain consecutive dots"}

      local =~ @local_part ->
        :ok

      true ->
        {:error, "contains characters not allowed before the @"}
    end
  end

  defp check_domain("[" <> _), do: {:error, "IP-address domains aren't supported"}

  defp check_domain(domain) do
    labels = String.split(domain, ".")

    cond do
      length(labels) < 2 ->
        {:error, "domain must have at least two labels, like example.com"}

      Enum.any?(labels, &(&1 == "")) ->
        {:error, "domain must not contain empty labels or consecutive dots"}

      Enum.any?(labels, &(byte_size(&1) > @max_label)) ->
        {:error, "each part of the domain must be at most #{@max_label} characters"}

      not Enum.all?(labels, &(&1 =~ @label)) ->
        {:error,
         "domain may only use letters, digits and hyphens, not at the start or end of a part"}

      List.last(labels) =~ ~r/\A[0-9]+\z/ ->
        {:error, "domain must end in a top-level domain, not a number"}

      true ->
        :ok
    end
  end

  # Error messages quote the offending entry; keep a pasted essay from flooding
  # the form, and never echo raw control characters back into the page.
  defp display(address) when is_binary(address) do
    cleaned = String.replace(address, ~r/[\x00-\x1F\x7F]/, " ")

    if String.length(cleaned) > 60, do: String.slice(cleaned, 0, 57) <> "...", else: cleaned
  end

  defp display(other), do: inspect(other)
end
