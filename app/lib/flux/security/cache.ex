defmodule Flux.Security.Cache do
  @moduledoc """
  Small in-memory cache for per-org IP allowlists, so the `IpAllowlist` plug
  does not hit Postgres on every API request (the authenticated API path,
  including webhook ingestion, is hot).

  Entries hold the org's **parsed** CIDR ranges (`InetCidr` tuples) and expire
  after a short TTL; `Flux.Security.update_settings/2` busts the entry
  immediately on change. A named, public, read-optimized ETS table backs it; the
  owning GenServer exists only to hold the table (same pattern as
  `Flux.RateLimiter`).
  """

  use GenServer

  @table __MODULE__
  @ttl_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Returns the org's cached parsed CIDR list, loading via `loader` (a 0-arity
  function returning the parsed list) on a miss or after the TTL expires.
  """
  @spec fetch(term(), (-> [tuple()])) :: [tuple()]
  def fetch(org_id, loader) when is_function(loader, 0) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, org_id) do
      [{^org_id, parsed, expiry}] when expiry > now ->
        parsed

      _ ->
        parsed = loader.()
        :ets.insert(@table, {org_id, parsed, now + @ttl_ms})
        parsed
    end
  end

  @doc "Evicts an org's cached allowlist (called after an update)."
  @spec bust(term()) :: :ok
  def bust(org_id) do
    :ets.delete(@table, org_id)
    :ok
  end

  @doc "Clears the whole cache. For tests."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, nil}
  end
end
