defmodule FluxWeb.Plugs.ClientIp do
  @moduledoc """
  Resolves `conn.remote_ip` to the real client IP.

  `RemoteIp` always trusts `X-Forwarded-For` from the immediate connection, so
  it is only safe to apply when we actually sit behind a proxy. Therefore:

      config :flux, FluxWeb.Plugs.ClientIp, proxies: ["10.0.0.0/8", ...]

  (env `FLUX_TRUSTED_PROXIES`, comma-separated CIDRs).

  - **No trusted proxies configured (default):** this plug is a no-op —
    `conn.remote_ip` stays the TCP peer, which is unspoofable. A client sending
    a forged `X-Forwarded-For` cannot change its resolved IP.
  - **Trusted proxies configured:** `RemoteIp` resolves the real client IP by
    walking `X-Forwarded-For` past the listed proxy hops.

  Correcting `remote_ip` here benefits every downstream consumer — the IP
  allowlist, `FluxWeb.AuditMeta`, and webhook logging.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case remote_ip_opts() do
      :disabled -> conn
      opts -> RemoteIp.call(conn, opts)
    end
  end

  # Returns compiled RemoteIp opts, or :disabled when no trusted proxies are
  # configured. Parsing the proxy CIDRs is not free, so cache the compiled opts
  # in :persistent_term keyed by the configured proxy list (recomputed
  # automatically if the config changes).
  defp remote_ip_opts do
    proxies = Application.get_env(:flux, __MODULE__, [])[:proxies] || []
    key = {__MODULE__, :opts, proxies}

    case :persistent_term.get(key, :unset) do
      :unset ->
        opts = if proxies == [], do: :disabled, else: build_opts(proxies)
        :persistent_term.put(key, opts)
        opts

      opts ->
        opts
    end
  end

  defp build_opts(proxies), do: RemoteIp.init(headers: ~w[x-forwarded-for], proxies: proxies)
end
