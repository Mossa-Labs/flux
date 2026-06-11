defmodule Flux.Alerts.Registry do
  @moduledoc """
  Single-provider registry for the active `Flux.Alerts.Provider`.

  Seeded at boot from `config :flux, Flux.Alerts, provider: ...` (defaulting to
  the Community stub via `Flux.Registrations`); the commercial edition overrides
  this to a Postgres-backed provider once the `:alerting` feature is entitled.

  Mirrors `Flux.Metering.Registry`: an ETS single-entry table gives lock-free
  reads (the gated LiveView resolves the provider on every mount/action).
  """

  use GenServer

  @table __MODULE__
  @key :__active__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec set_active(module()) :: :ok
  def set_active(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:set_active, module})
  end

  @spec active() :: module()
  def active do
    case :ets.lookup(@table, @key) do
      [{@key, module}] ->
        module

      [] ->
        raise "No active alerts provider. Set config :flux, Flux.Alerts, provider: Flux.Alerts.Providers.Community (or another provider)."
    end
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:set_active, module}, _from, state) do
    :ets.insert(@table, {@key, module})
    {:reply, :ok, state}
  end
end
