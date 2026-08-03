defmodule Flux.Branding.Registry do
  @moduledoc """
  Single-provider registry for the active `Flux.Branding.Provider` (MOS-483).

  Seeded at boot from `config :flux, Flux.Branding, provider: ...` (defaulting to
  the Community stub via `Flux.Registrations`); the commercial edition overrides
  it once `:white_label` is entitled.

  Mirrors `Flux.Accounts.PasswordPolicy.Registry` — an ETS single-entry table for
  lock-free reads, since branding is resolved on every page render.
  """

  use GenServer

  @table __MODULE__
  @key :__active__

  # Fallback when the registry isn't up — seeds, release migrations, and `eval`
  # contexts that start only the Repo. Branding is read while rendering the
  # sign-in page, so this must answer rather than raise: stock Flux is always a
  # correct answer, and it is exactly the ungated behaviour.
  #
  # Deliberately NOT the raise-on-miss shape used by Flux.Audit.Registry. An
  # audit write that cannot find its provider should fail loudly; a page that
  # cannot find its branding should render.
  @default_provider Flux.Branding.Providers.Community

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
