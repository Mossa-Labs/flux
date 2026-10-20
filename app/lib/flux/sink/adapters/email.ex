defmodule Flux.Sink.Adapters.Email do
  @moduledoc """
  Email sink adapter using Swoosh.

  Sends one email per pipeline record to a fixed list of recipients, with a
  subject and body rendered from `{field}` templates (see `Flux.Sink.Template`).

  ## Configuration

      %{
        "type" => "email",
        "provider" => "smtp",                     # Required — see Providers
        "from" => "alerts@example.com",           # Required (optional for "system")
        "from_name" => "Pipeline Alerts",         # Optional display name
        "reply_to" => "ops@example.com",          # Optional
        "to" => ["ops@example.com"],              # Required, 1+ addresses
        "cc" => [], "bcc" => [],                  # Optional
        "subject" => "Order {order.id} failed",   # Required, {field} template
        "html_body" => "<p>{error.message}</p>",  # Optional, {field} template
        "text_body" => "{error.message}",         # Optional, {field} template
        "rate_limit" => %{                        # Optional
          "max_per_minute" => 30,                 # Default: 30
          "max_wait_ms" => 30000                  # Default: 30000
        }
      }

  Recipients are fixed per sink and never read from the record, so upstream
  data cannot redirect mail. Every address must pass `Flux.EmailAddress`.

  When both bodies are set the email is multipart HTML + plain text. With only
  `html_body`, the plain-text part is derived from the rendered HTML. With
  neither, the body is the record as pretty-printed JSON.

  ## Providers

    * `"smtp"` — `host`, `port` (default 587, or 465 for `ssl`), `security`
      (`"starttls"` default, `"ssl"`, or `"none"`), optional
      `username`/`password`, and `tls_verify` (default `true`).
    * `"system"` — the operator's own mailer (`Flux.Mailer`, configured with
      `FLUX_SMTP_*`). No credentials; `from` defaults to `FLUX_MAIL_FROM_*`.
    * `"sendgrid"`, `"postmark"` — `api_key`.
    * `"mailgun"` — `api_key`, `domain`, optional `region` (`"us"` / `"eu"`).
    * `"amazon_ses"` — `region`, `access_key`, `secret_access_key`.

  API providers also accept an optional `base_url` to point at a regional or
  compatible endpoint.

  ## Delivery semantics

  Sink delivery is fire-and-forget: the pipeline acknowledges the record
  whether or not the email goes out. To avoid being flagged as spam, each sink
  sends at most `max_per_minute` emails per node; a record over the limit waits
  up to `max_wait_ms` for the next window and is then dropped with
  `{:error, :rate_limited}`.
  """

  @behaviour Flux.Sink.Adapter

  import Swoosh.Email

  require Logger

  alias Flux.EmailAddress
  alias Flux.Sink.Template

  @providers ~w(smtp system sendgrid mailgun postmark amazon_ses)
  @securities ~w(starttls ssl none)
  @mailgun_regions %{
    "us" => "https://api.mailgun.net/v3",
    "eu" => "https://api.eu.mailgun.net/v3"
  }

  # RFC 5322 recommends header lines of at most 78 characters; a display name
  # longer than that is almost certainly a mistake.
  @max_from_name 78
  @max_subject 500

  @default_max_per_minute 30
  @default_max_wait_ms 30_000
  @rate_window_ms 60_000
  @rate_poll_ms 250

  @doc "The supported provider identifiers."
  @spec providers() :: [String.t()]
  def providers, do: @providers

  @impl Flux.Sink.Adapter
  def deliver(data, config, opts) do
    provider = config["provider"]

    with :ok <- acquire_slot(config, opts),
         {:ok, config} <- resolve_sender(config),
         email = build_email(data, config),
         {:ok, mailer_config} <- swoosh_config(config) do
      case send_email(email, override_adapter(mailer_config)) do
        {:ok, _receipt} ->
          :ok

        {:error, reason} ->
          Logger.error("Email sink delivery failed",
            provider: provider,
            sink_id: opts[:sink_id],
            reason: inspect(reason)
          )

          {:error, {:email_error, reason}}
      end
    else
      {:error, :rate_limited} = error ->
        Logger.warning("Email sink rate limit reached; record dropped",
          provider: provider,
          sink_id: opts[:sink_id]
        )

        error

      {:error, _reason} = error ->
        error
    end
  end

  # Swoosh raises on a malformed adapter config and gen_smtp can exit on a
  # socket failure; either should surface as a delivery error, not a crash.
  defp send_email(email, mailer_config) do
    Swoosh.Mailer.deliver(email, mailer_config)
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  # Tests swap the transport for `Swoosh.Adapters.Test` so delivery can be
  # asserted without a network.
  defp override_adapter(mailer_config) do
    case Application.get_env(:flux, :email_sink_swoosh_adapter) do
      nil -> mailer_config
      adapter -> [adapter: adapter]
    end
  end

  # ── Building the email ───────────────────────────────────────────────────

  @doc """
  Builds the `Swoosh.Email` for one record. Pure — no delivery, no lookups —
  so templates, recipients and the multipart body can be unit-tested.
  """
  @spec build_email(map(), map()) :: Swoosh.Email.t()
  def build_email(data, config) do
    new()
    |> from({config["from_name"] || "", config["from"]})
    |> to(recipients(config, "to"))
    |> cc(recipients(config, "cc"))
    |> bcc(recipients(config, "bcc"))
    |> maybe_reply_to(config["reply_to"])
    |> subject(Template.interpolate_header(config["subject"] || "", data))
    # RFC 3834: tells mail servers and out-of-office responders this is
    # machine-generated, so they don't reply to it.
    |> header("Auto-Submitted", "auto-generated")
    |> put_bodies(data, config)
  end

  defp recipients(config, key) do
    case config[key] do
      list when is_list(list) -> list
      value when is_binary(value) -> EmailAddress.split_list(value)
      _ -> []
    end
  end

  defp maybe_reply_to(email, address) when is_binary(address) and address != "",
    do: reply_to(email, address)

  defp maybe_reply_to(email, _), do: email

  defp put_bodies(email, data, config) do
    case {present(config["html_body"]), present(config["text_body"])} do
      {nil, nil} ->
        text_body(email, Jason.encode!(data, pretty: true))

      {html, nil} ->
        rendered = Template.interpolate_html(html, data)
        email |> html_body(rendered) |> text_body(html_to_text(rendered))

      {nil, text} ->
        text_body(email, Template.interpolate(text, data))

      {html, text} ->
        email
        |> html_body(Template.interpolate_html(html, data))
        |> text_body(Template.interpolate(text, data))
    end
  end

  # A readable plain-text alternative for HTML-only templates: block-level tags
  # become line breaks, the rest are dropped, and the entities that
  # `Phoenix.HTML.html_escape/1` produces are decoded.
  defp html_to_text(html) do
    html
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/(p|div|h[1-6]|li|tr|table|ul|ol)>/i, "\n")
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # The "system" provider sends as the operator's configured sender unless the
  # sink names its own.
  defp resolve_sender(%{"provider" => "system"} = config) do
    case {present(config["from"]), Flux.Mailer.from()} do
      {nil, nil} ->
        {:error, :mailer_not_configured}

      {nil, {name, address}} ->
        {:ok, config |> Map.put("from", address) |> Map.put_new("from_name", name)}

      _ ->
        {:ok, config}
    end
  end

  defp resolve_sender(config), do: {:ok, config}

  # ── Transport config ─────────────────────────────────────────────────────

  @doc """
  Builds the Swoosh adapter keyword list for the sink's provider.

  Each provider gets only its own credentials. The `"system"` provider is the
  one case that reads `Flux.Mailer`'s config; every other provider is built
  from the sink alone, so the operator's relay credentials never mix into a
  user's sink.
  """
  @spec swoosh_config(map()) :: {:ok, keyword()} | {:error, term()}
  def swoosh_config(%{"provider" => "smtp"} = config), do: {:ok, smtp_config(config)}

  def swoosh_config(%{"provider" => "system"}) do
    case Application.get_env(:flux, Flux.Mailer, [])[:adapter] do
      nil -> {:error, :mailer_not_configured}
      _ -> {:ok, Application.get_env(:flux, Flux.Mailer)}
    end
  end

  def swoosh_config(%{"provider" => "sendgrid"} = config) do
    {:ok,
     [adapter: Swoosh.Adapters.Sendgrid, api_key: config["api_key"]]
     |> put_base_url(config, :base_url)}
  end

  def swoosh_config(%{"provider" => "postmark"} = config) do
    {:ok,
     [adapter: Swoosh.Adapters.Postmark, api_key: config["api_key"]]
     |> put_base_url(config, :base_url)}
  end

  def swoosh_config(%{"provider" => "mailgun"} = config) do
    base = [
      adapter: Swoosh.Adapters.Mailgun,
      api_key: config["api_key"],
      domain: config["domain"]
    ]

    base =
      case Map.fetch(@mailgun_regions, config["region"] || "us") do
        {:ok, url} -> Keyword.put(base, :base_url, url)
        :error -> base
      end

    {:ok, put_base_url(base, config, :base_url)}
  end

  def swoosh_config(%{"provider" => "amazon_ses"} = config) do
    {:ok,
     [
       adapter: Swoosh.Adapters.AmazonSES,
       region: config["region"],
       access_key: config["access_key"],
       secret: config["secret_access_key"]
     ]
     |> put_base_url(config, :host)}
  end

  def swoosh_config(config), do: {:error, {:unknown_provider, config["provider"]}}

  defp put_base_url(opts, config, key) do
    case present(config["base_url"]) do
      nil -> opts
      url -> Keyword.put(opts, key, url)
    end
  end

  # Mirrors the hardened production mailer in config/runtime.exs: TLS is
  # required (not opportunistic) unless the sink explicitly opts out, and the
  # server certificate is verified against the OS trust store. Only keys gen_smtp
  # understands are passed through.
  defp smtp_config(config) do
    host = config["host"]
    security = config["security"] || "starttls"
    port = parse_int(config["port"]) || if(security == "ssl", do: 465, else: 587)
    username = present(config["username"])

    tls_opts = tls_options(host, Map.get(config, "tls_verify", true) != false)

    [
      adapter: Swoosh.Adapters.SMTP,
      relay: host,
      port: port,
      auth: if(username, do: :always, else: :never),
      # The sink names the exact host to connect to; don't resolve MX records.
      no_mx_lookups: true,
      retries: 1
    ]
    |> Keyword.merge(security_opts(security, tls_opts))
    |> then(fn opts ->
      if username,
        do: Keyword.merge(opts, username: username, password: config["password"] || ""),
        else: opts
    end)
  end

  defp security_opts("ssl", tls_opts), do: [ssl: true, tls: :never, sockopts: tls_opts]
  defp security_opts("none", _tls_opts), do: [ssl: false, tls: :never]
  defp security_opts(_starttls, tls_opts), do: [ssl: false, tls: :always, tls_options: tls_opts]

  defp tls_options(_host, false), do: [verify: :verify_none]

  defp tls_options(host, true) do
    base = [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3]
    charlist = String.to_charlist(host || "")

    # SNI must name a host, never an IP address.
    case :inet.parse_address(charlist) do
      {:ok, _ip} -> base
      {:error, _} -> Keyword.put(base, :server_name_indication, charlist)
    end
  end

  # ── Rate limiting ────────────────────────────────────────────────────────

  # Waits for a send slot in this sink's per-minute window, polling until
  # `max_wait_ms` has passed. Keyed by sink id so sinks don't share a budget.
  defp acquire_slot(config, opts) do
    rate = if is_map(config["rate_limit"]), do: config["rate_limit"], else: %{}
    limit = parse_int(rate["max_per_minute"]) || @default_max_per_minute
    max_wait = parse_int(rate["max_wait_ms"]) || @default_max_wait_ms
    window = parse_int(rate["window_ms"]) || @rate_window_ms
    key = {:email_sink, opts[:sink_id] || :erlang.phash2(config)}

    wait_for_slot(key, limit, window, now_ms() + max_wait)
  end

  defp wait_for_slot(key, limit, window, deadline) do
    remaining = deadline - now_ms()

    cond do
      Flux.RateLimiter.allow?(key, limit, window) ->
        :ok

      remaining <= 0 ->
        {:error, :rate_limited}

      true ->
        Process.sleep(min(@rate_poll_ms, remaining))
        wait_for_slot(key, limit, window, deadline)
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  # ── Validation ───────────────────────────────────────────────────────────

  @impl Flux.Sink.Adapter
  def validate_config(config) do
    Flux.Sink.Validation.run(
      config,
      [
        &validate_provider/1,
        &validate_from/1,
        &validate_from_name/1,
        &validate_reply_to/1,
        &validate_subject/1,
        &validate_bodies/1,
        &validate_recipient_count/1,
        &validate_rate_limit/1
      ] ++
        Enum.map(~w(to cc bcc), fn key -> &validate_recipients(&1, key) end) ++
        provider_rules(config["provider"])
    )
  end

  defp provider_rules("smtp"),
    do: [&validate_host/1, &validate_port/1, &validate_security/1, &validate_smtp_auth/1]

  defp provider_rules(p) when p in ~w(sendgrid postmark),
    do: [&require_key(&1, "api_key"), &validate_base_url/1]

  defp provider_rules("mailgun"),
    do: [
      &require_key(&1, "api_key"),
      &require_key(&1, "domain"),
      &validate_mailgun_region/1,
      &validate_base_url/1
    ]

  defp provider_rules("amazon_ses"),
    do: [
      &require_key(&1, "region"),
      &require_key(&1, "access_key"),
      &require_key(&1, "secret_access_key"),
      &validate_base_url/1
    ]

  defp provider_rules(_), do: []

  defp validate_provider(config) do
    case config["provider"] do
      p when p in @providers -> :ok
      nil -> {:error, "provider is required"}
      _ -> {:error, "provider must be one of: #{Enum.join(@providers, ", ")}"}
    end
  end

  defp validate_from(%{"provider" => "system"} = config) do
    if present(config["from"]), do: validate_address(config, "from"), else: :ok
  end

  defp validate_from(config) do
    if present(config["from"]),
      do: validate_address(config, "from"),
      else: {:error, "from address is required"}
  end

  defp validate_from_name(config) do
    case config["from_name"] do
      nil ->
        :ok

      name when is_binary(name) ->
        cond do
          String.length(name) > @max_from_name ->
            {:error, "from_name must be at most #{@max_from_name} characters"}

          name =~ ~r/[\x00-\x1F\x7F]/ ->
            {:error, "from_name must not contain line breaks or control characters"}

          true ->
            :ok
        end

      _ ->
        {:error, "from_name must be a string"}
    end
  end

  defp validate_reply_to(config) do
    if present(config["reply_to"]), do: validate_address(config, "reply_to"), else: :ok
  end

  defp validate_address(config, key) do
    case EmailAddress.validate(config[key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, ~s(#{key}: "#{config[key]}" #{reason})}
    end
  end

  defp validate_recipients(config, key) do
    case {key, EmailAddress.validate_list(config[key])} do
      {"to", {:ok, []}} -> {:error, "to must include at least one recipient"}
      {_, {:ok, _}} -> :ok
      {_, {:error, reasons}} -> {:error, "#{key}: " <> Enum.join(reasons, "; ")}
    end
  end

  defp validate_recipient_count(config) do
    total =
      ~w(to cc bcc)
      |> Enum.map(&recipients(config, &1))
      |> Enum.map(&length/1)
      |> Enum.sum()

    if total > EmailAddress.max_recipients(),
      do:
        {:error,
         "at most #{EmailAddress.max_recipients()} recipients are allowed across to, cc and bcc"},
      else: :ok
  end

  defp validate_subject(config) do
    case config["subject"] do
      s when is_binary(s) and s != "" ->
        if String.length(s) > @max_subject,
          do: {:error, "subject must be at most #{@max_subject} characters"},
          else: :ok

      _ ->
        {:error, "subject is required"}
    end
  end

  defp validate_bodies(config) do
    if Enum.all?(~w(html_body text_body), &(is_nil(config[&1]) or is_binary(config[&1]))),
      do: :ok,
      else: {:error, "html_body and text_body must be strings"}
  end

  defp validate_rate_limit(config) do
    case config["rate_limit"] do
      nil ->
        :ok

      %{} = rate ->
        with :ok <- int_in_range(rate, "max_per_minute", 1..10_000),
             :ok <- int_in_range(rate, "max_wait_ms", 0..300_000) do
          int_in_range(rate, "window_ms", 1..3_600_000)
        end

      _ ->
        {:error, "rate_limit must be a map"}
    end
  end

  defp int_in_range(map, key, first..last//_) do
    case map[key] do
      nil -> :ok
      n when is_integer(n) and n >= first and n <= last -> :ok
      _ -> {:error, "rate_limit.#{key} must be an integer between #{first} and #{last}"}
    end
  end

  defp validate_host(config) do
    case present(config["host"]) do
      nil ->
        {:error, "host is required"}

      host ->
        if host =~ ~r/\A[A-Za-z0-9.\-:\[\]]+\z/,
          do: :ok,
          else: {:error, "host must be a hostname or IP address (no scheme or path)"}
    end
  end

  defp validate_port(config) do
    case config["port"] do
      nil -> :ok
      p when is_integer(p) and p in 1..65_535 -> :ok
      _ -> {:error, "port must be an integer between 1 and 65535"}
    end
  end

  defp validate_security(config) do
    case config["security"] do
      nil -> :ok
      s when s in @securities -> :ok
      _ -> {:error, "security must be one of: #{Enum.join(@securities, ", ")}"}
    end
  end

  defp validate_smtp_auth(config) do
    if present(config["username"]) && !present(config["password"]),
      do: {:error, "password is required when a username is set"},
      else: :ok
  end

  defp validate_mailgun_region(config) do
    case config["region"] do
      nil -> :ok
      r when is_map_key(@mailgun_regions, r) -> :ok
      _ -> {:error, "region must be \"us\" or \"eu\""}
    end
  end

  defp validate_base_url(config) do
    case present(config["base_url"]) do
      nil ->
        :ok

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
            :ok

          _ ->
            {:error, "base_url must be a valid HTTP/HTTPS URL"}
        end
    end
  end

  defp require_key(config, key) do
    if present(config[key]), do: :ok, else: {:error, "#{key} is required"}
  end

  # ── Connection test ──────────────────────────────────────────────────────

  @doc """
  Checks the transport without sending mail. For SMTP this connects,
  negotiates TLS and authenticates, then hangs up. The `"system"` provider
  reports whether the operator's mailer is configured. API providers have no
  side-effect-free credential check, so they return `:ok`.
  """
  @impl Flux.Sink.Adapter
  def test_connection(%{"provider" => "smtp"} = config) do
    options =
      config
      |> smtp_config()
      |> Keyword.delete(:adapter)
      |> Swoosh.Adapters.SMTP.gen_smtp_config()

    case :gen_smtp_client.open(options) do
      {:ok, socket} ->
        :gen_smtp_client.close(socket)
        :ok

      {:error, type, details} ->
        {:error, {type, details}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def test_connection(%{"provider" => "system"}) do
    if Flux.Mailer.configured?(), do: :ok, else: {:error, :mailer_not_configured}
  end

  def test_connection(_config), do: :ok

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
