defmodule Flux.Accounts.MfaEnforcement.Registry do
  @moduledoc """
  Single-provider registry for the active `Flux.Accounts.MfaEnforcement.Provider`
  (MOS-591).

  Seeded at boot from `config :flux, Flux.Accounts.MfaEnforcement, provider: ...`
  (defaulting to the Community no-op stub via `Flux.Registrations`); the Enterprise
  edition overrides this to the real provider once `:mfa_enforcement` is entitled.

  Mirrors `Flux.Accounts.PasswordPolicy.Registry`: an ETS single-entry table gives
  lock-free reads (the active provider is resolved on every login and protected mount).
  """

  use GenServer

  @table __MODULE__
  @key :__active__

  # Fallback when the registry isn't up (seeds / release migration / eval contexts
  # that start only the Repo). Enforcement must default to off there.
  @default_provider Flux.Accounts.MfaEnforcement.Providers.Community

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec set_active(module()) :: :ok
  def set_active(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:set_active, module})
  end

  @spec active() :: module()
  def active do
    case :ets.whereis(@table) do
      :undefined ->
        @default_provider

      _tid ->
        case :ets.lookup(@table, @key) do
          [{@key, module}] -> module
          [] -> @default_provider
        end
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
