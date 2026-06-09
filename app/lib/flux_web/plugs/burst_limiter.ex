defmodule FluxWeb.Plugs.BurstLimiter do
  @moduledoc """
  Per-API-key burst rate limiter (MOS-450) — a Community safety valve, not a
  monetization feature: it applies identically on every license tier.

  Caps each authenticated API key at a fixed number of requests per window
  (default 1,000 req/sec). Over the limit returns `429 Too Many Requests` with
  `Retry-After: 1` and halts. A breach logs a warning at most once per key per
  hour and emits `[:flux, :api, :burst_limited]` telemetry.

  Must run AFTER `FluxWeb.Plugs.ApiAuth` in the `:api_authenticated` pipeline, so
  the API key is known. Keyed on the per-org key id; the deprecated global key
  (no id) falls back to a per-organization bucket.
  """

  import Plug.Conn

  require Logger

  @behaviour Plug

  @default_limit 1_000
  @default_window_ms 1_000
  @warn_window_ms 3_600_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    {limit, window_ms} = config()
    key = rate_key(conn)

    if Flux.RateLimiter.allow?({:burst, key}, limit, window_ms) do
      conn
    else
      on_limit(conn, key)
    end
  end

  defp rate_key(conn) do
    case conn.assigns[:api_key_id] do
      nil -> {:legacy_global, org_id(conn)}
      id -> {:api_key, id}
    end
  end

  defp on_limit(conn, key) do
    maybe_warn(conn, key)

    :telemetry.execute([:flux, :api, :burst_limited], %{count: 1}, %{
      api_key_id: conn.assigns[:api_key_id],
      organization_id: org_id(conn)
    })

    conn
    |> put_resp_header("retry-after", "1")
    |> put_status(:too_many_requests)
    |> Phoenix.Controller.json(%{
      error: "rate_limited",
      message: "Rate limit exceeded. Retry after 1 second."
    })
    |> halt()
  end

  # Log the first burst for a key within an hour, then stay quiet — re-using the
  # rate limiter itself as a once-per-hour gate.
  defp maybe_warn(conn, key) do
    if Flux.RateLimiter.allow?({:burst_warn, key}, 1, @warn_window_ms) do
      Logger.warning(
        "[BurstLimiter] API key #{inspect(conn.assigns[:api_key_id])} " <>
          "(org #{inspect(org_id(conn))}) exceeded the request rate limit."
      )
    end
  end

  defp org_id(conn) do
    case conn.assigns[:current_scope] do
      %{organization_id: org_id} -> org_id
      _ -> nil
    end
  end

  defp config do
    opts = Application.get_env(:flux, __MODULE__, [])
    {Keyword.get(opts, :limit, @default_limit), Keyword.get(opts, :window_ms, @default_window_ms)}
  end
end
