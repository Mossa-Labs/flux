defmodule Flux.RateLimiter do
  @moduledoc """
  A small, in-memory fixed-window rate limiter shared by the abuse-protection
  safety valves (MOS-450): per-API-key burst limiting, per-org / node-wide
  pipeline-start limiting, and once-per-interval log de-duplication.

  Each `key` gets a 2-slot Erlang `:atomics` array `[count, window_start_ms]`,
  stored in a named, `:public`, write-concurrent ETS table. `allow?/3`:

    * lazily creates the counter (race-safe via `:ets.insert_new/2`),
    * resets the window when `now - window_start >= window_ms`,
    * `:atomics.add_get/3` the count and returns whether it is within `limit`.

  Reads/writes on the hot path are lock-free (atomics); the owning GenServer
  exists only to own the ETS table. The window reset is lazy and per-entry, so a
  single table supports any mix of window sizes (1s burst, 60s starts, 1h warn
  de-dup). Minor reset races are acceptable — this is a coarse safety valve, not
  an accounting system.

  ## Scope: per node

  Counters are **node-local** — there is no shared/distributed state. Under
  multi-node HA (a Pro/Enterprise feature) every node enforces these limits
  independently, so the effective cluster-wide allowance for a given key is
  roughly `node_count × limit`. That is intentional: these valves protect each
  node's resources (connections, Broadway spawn, memory). Account-level limits
  that must hold across the whole fleet belong elsewhere — e.g. the
  Postgres-backed monthly usage quota — not here.
  """

  use GenServer

  @table __MODULE__

  # ── Public API ─────────────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records one hit against `key` and returns whether it is within `limit` for the
  current `window_ms` window. The first `limit` calls in a window return `true`;
  further calls return `false` until the window rolls over.
  """
  @spec allow?(term(), pos_integer(), pos_integer()) :: boolean()
  def allow?(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)
    ref = counter(key, now)
    window_start = :atomics.get(ref, 2)

    if now - window_start >= window_ms do
      # New window. Concurrent callers may race here; for a safety valve a brief
      # over/under-count at the boundary is fine.
      :atomics.put(ref, 2, now)
      :atomics.put(ref, 1, 0)
    end

    :atomics.add_get(ref, 1, 1) <= limit
  end

  @doc "Clears all counters. For tests."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  # ── Server ─────────────────────────────────────────────────────────────────

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, nil}
  end

  # Fetch the atomics ref for `key`, creating it on first use. The window start
  # is seeded to `now` (a real monotonic timestamp) so the first window is
  # measured correctly — monotonic time can be negative, so a 0 default would
  # mis-trigger the rollover. `insert_new` makes the create race-safe: if another
  # process won, we re-read its ref.
  defp counter(key, now) do
    case :ets.lookup(@table, key) do
      [{^key, ref}] ->
        ref

      [] ->
        ref = :atomics.new(2, [])
        :atomics.put(ref, 2, now)

        if :ets.insert_new(@table, {key, ref}) do
          ref
        else
          [{^key, existing}] = :ets.lookup(@table, key)
          existing
        end
    end
  end
end
