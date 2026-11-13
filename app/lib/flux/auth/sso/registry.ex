defmodule Flux.Auth.SSO.Registry do
  @moduledoc """
  Single-provider registry for the active `Flux.Auth.SSO.Provider`.

  Seeded at boot from `config :flux, Flux.Auth.SSO, provider: ...` (defaulting to
  the Community stub via `Flux.Registrations`), and overridden at runtime once
  `:sso` is entitled.

  Mirrors `Flux.Accounts.MfaEnforcement.Registry`: an ETS single-entry table for
  lock-free reads, since the sign-in page and every password login consult it.
  """

  use GenServer

  @table __MODULE__
  @key :__active__

  # Fallback when the registry isn't up (seeds, release migrations, eval contexts
  # that start only the Repo). SSO must default to off there: unavailable, never
  # enforced.
  @default_provider Flux.Auth.SSO.Providers.Community

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
