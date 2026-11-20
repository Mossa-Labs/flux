defmodule Flux.Queue.Naming do
  @moduledoc """
  Maps a pipeline's *logical* queue name to the *physical* broker queue that
  holds it, inside one organization.

  Users, pipelines, imports and exports only ever deal in logical names such as
  `"webhooks.stripe"`. The server places every logical name inside the calling
  organization's namespace before it reaches the broker:

      "webhooks.stripe"  --(organization 42)-->  "org.42.webhooks.stripe"

  The organization always comes from the server (an API key, the pipeline row,
  a source row), never from the name, so two organizations that pick the same
  logical name get two separate queues, and no logical name can address a queue
  outside its organization. `Flux.Queue` is the only caller that turns a logical
  name into a physical one; adapters only ever see physical names.

  ## Logical names

  A logical name starts with a letter or digit, contains only `A-Z a-z 0-9 _ . -`
  (so never a RabbitMQ topic wildcard `*` or `#`), is at most
  200 bytes long (so the physical name fits a broker's 255-byte limit), and
  doesn't start with a reserved prefix (`org.`, `amq.`, `flux.`, in any case):

    * `org.` is the namespace itself.
    * `amq.` is reserved by AMQP brokers.
    * `flux.` is kept for Flux's own per-organization queues, such as the
      dead-letter queue `org.<id>.flux.dlq`.
  """

  @max_logical_bytes 200
  # Room for a source-type prefix (such as `"<type>."` or `"<type>.<group>."`)
  # in front of one sanitized segment, inside the logical-name limit.
  @segment_bytes 120
  @reserved_prefixes ~w(org. amq. flux.)
  @logical_format ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/
  @physical_format ~r/\Aorg\.([1-9][0-9]*)\.(.+)\z/s

  @type org_id :: pos_integer()
  @type logical :: String.t()
  @type physical :: String.t()
  @type invalid_reason :: :blank | :too_long | :invalid_characters | :reserved_prefix

  @doc "Maximum length, in bytes, of a logical queue name."
  @spec max_logical_bytes() :: pos_integer()
  def max_logical_bytes, do: @max_logical_bytes

  @doc """
  Checks that `name` is a valid logical queue name.

      iex> Flux.Queue.Naming.validate_logical("webhooks.stripe")
      :ok

      iex> Flux.Queue.Naming.validate_logical("org.7.webhooks.stripe")
      {:error, :reserved_prefix}
  """
  @spec validate_logical(term()) :: :ok | {:error, invalid_reason()}
  def validate_logical(name) when is_binary(name) do
    cond do
      name == "" -> {:error, :blank}
      byte_size(name) > @max_logical_bytes -> {:error, :too_long}
      not Regex.match?(@logical_format, name) -> {:error, :invalid_characters}
      reserved?(name) -> {:error, :reserved_prefix}
      true -> :ok
    end
  end

  def validate_logical(nil), do: {:error, :blank}
  def validate_logical(_name), do: {:error, :invalid_characters}

  @doc "Returns `true` if `name` is a valid logical queue name."
  @spec valid_logical?(term()) :: boolean()
  def valid_logical?(name), do: validate_logical(name) == :ok

  @doc "A human-readable message for a `validate_logical/1` error, for changesets."
  @spec error_message(invalid_reason()) :: String.t()
  def error_message(:blank), do: "can't be blank"
  def error_message(:too_long), do: "must be at most #{@max_logical_bytes} bytes"

  def error_message(:invalid_characters),
    do: "must start with a letter or digit and contain only letters, digits, '_', '.' and '-'"

  def error_message(:reserved_prefix),
    do: "can't start with a reserved prefix (#{Enum.join(@reserved_prefixes, ", ")})"

  @doc """
  The physical queue name for `logical` inside organization `org_id`.

      iex> Flux.Queue.Naming.physical(42, "webhooks.stripe")
      {:ok, "org.42.webhooks.stripe"}
  """
  @spec physical(term(), term()) ::
          {:ok, physical()} | {:error, :organization_required | invalid_reason()}
  def physical(org_id, logical) do
    with :ok <- validate_org(org_id),
         :ok <- validate_logical(logical) do
      {:ok, prefix(org_id) <> logical}
    end
  end

  @doc "Like `physical/2`, but raises `ArgumentError` on invalid input."
  @spec physical!(org_id(), logical()) :: physical()
  def physical!(org_id, logical) do
    case physical(org_id, logical) do
      {:ok, name} ->
        name

      {:error, reason} ->
        raise ArgumentError,
              "invalid queue #{inspect(logical)} for organization #{inspect(org_id)}: #{reason}"
    end
  end

  @doc """
  Splits a physical queue name into its organization and remainder.

  The remainder is not validated as a logical name, so this also recognizes an
  organization's own system queues (see `dead_letter_queue/1`).

      iex> Flux.Queue.Naming.owner("org.42.webhooks.stripe")
      {:ok, 42, "webhooks.stripe"}

      iex> Flux.Queue.Naming.owner("webhooks.stripe")
      :error
  """
  @spec owner(term()) :: {:ok, org_id(), String.t()} | :error
  def owner(physical) when is_binary(physical) do
    case Regex.run(@physical_format, physical, capture: :all_but_first) do
      [id, rest] -> {:ok, String.to_integer(id), rest}
      nil -> :error
    end
  end

  def owner(_physical), do: :error

  @doc """
  The logical name of `physical` if it belongs to organization `org_id`.

  Returns `:error` for a queue of another organization, a queue outside the
  namespace, or one of the organization's own system queues.
  """
  @spec logical(term(), term()) :: {:ok, logical()} | :error
  def logical(org_id, physical) do
    with :ok <- validate_org(org_id),
         {:ok, ^org_id, rest} <- owner(physical),
         :ok <- validate_logical(rest) do
      {:ok, rest}
    else
      _ -> :error
    end
  end

  @doc """
  Checks that `physical` is inside organization `org_id`'s namespace.

  Adapters call this before publishing, as a second line of defence behind
  `Flux.Queue`.
  """
  @spec check_owner(term(), term()) ::
          :ok | {:error, :organization_required | :organization_mismatch}
  def check_owner(physical, org_id) do
    with :ok <- validate_org(org_id) do
      case owner(physical) do
        {:ok, ^org_id, _rest} -> :ok
        _ -> {:error, :organization_mismatch}
      end
    end
  end

  @doc "The namespace prefix of organization `org_id`, e.g. `\"org.42.\"`."
  @spec prefix(org_id()) :: String.t()
  def prefix(org_id) when is_integer(org_id) and org_id > 0, do: "org.#{org_id}."

  @doc """
  The name of organization `org_id`'s dead-letter queue.

  It sits under the reserved `flux.` prefix, so no logical name maps onto it.

      iex> Flux.Queue.Naming.dead_letter_queue(42)
      "org.42.flux.dlq"
  """
  @spec dead_letter_queue(org_id()) :: physical()
  def dead_letter_queue(org_id) when is_integer(org_id) and org_id > 0,
    do: prefix(org_id) <> "flux.dlq"

  @doc """
  Turns arbitrary text into one segment a logical queue name can contain.

  Every character outside `A-Z a-z 0-9 _ . -` becomes `_`, and leading
  characters other than a letter or digit are dropped. Text that is already a
  valid segment of at most #{@segment_bytes} bytes comes back unchanged, so
  names that were already safe keep linking the same queue. Longer text is cut
  short and suffixed with a hash of the original, so distinct long inputs stay
  distinct. Source adapters use it on the parts of their queue names that come
  from external systems (topic names, subscriptions, remote queue names).

      iex> Flux.Queue.Naming.sanitize_segment("orders")
      "orders"

      iex> Flux.Queue.Naming.sanitize_segment("Orders Queue")
      "Orders_Queue"
  """
  @spec sanitize_segment(term()) :: String.t()
  def sanitize_segment(text) do
    text = to_string(text)

    cleaned =
      text
      |> String.replace(~r/[^A-Za-z0-9_.-]/u, "_")
      |> String.replace(~r/\A[^A-Za-z0-9]+/, "")

    cleaned = if cleaned == "", do: "x", else: cleaned

    if byte_size(cleaned) <= @segment_bytes, do: cleaned, else: shorten(cleaned, text)
  end

  defp shorten(cleaned, original) do
    hash = :crypto.hash(:sha256, original) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    binary_part(cleaned, 0, @segment_bytes - 9) <> "-" <> hash
  end

  defp reserved?(name) do
    downcased = String.downcase(name)
    Enum.any?(@reserved_prefixes, &String.starts_with?(downcased, &1))
  end

  defp validate_org(org_id) when is_integer(org_id) and org_id > 0, do: :ok
  defp validate_org(_org_id), do: {:error, :organization_required}
end
