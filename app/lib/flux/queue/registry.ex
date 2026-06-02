defmodule Flux.Queue.Registry do
  @moduledoc """
  Runtime lookup table for queue adapters.

  Community adapters (Memory) self-register at boot; Pro adapters (RabbitMQ,
  Kafka) register from the commercial edition at boot. Looked up by string type
  identifier such as `"memory"` or `"rabbitmq"`.

  The `:active` entry resolves to the queue adapter that `Flux.Queue`
  publishes through by default; configured via `config :flux, Flux.Queue,
  type: "memory"` and seeded at boot.
  """

  use GenServer

  @table __MODULE__

  @type type_name :: String.t()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec register(type_name(), module()) :: :ok
  def register(type, module) when is_binary(type) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, type, module})
  end

  @spec set_active(type_name()) :: :ok | {:error, :unknown_type}
  def set_active(type) when is_binary(type) do
    case lookup(type) do
      {:ok, _module} -> GenServer.call(__MODULE__, {:set_active, type})
      error -> error
    end
  end

  @spec active() :: {:ok, module()} | {:error, :no_active_adapter}
  def active do
    case :ets.lookup(@table, :__active__) do
      [{:__active__, type}] -> lookup(type) |> unwrap_active()
      [] -> {:error, :no_active_adapter}
    end
  end

  @spec lookup(type_name() | atom()) :: {:ok, module()} | {:error, :unknown_type}
  def lookup(type) when is_atom(type) and type != :__active__, do: lookup(Atom.to_string(type))

  def lookup(type) when is_binary(type) do
    case :ets.lookup(@table, type) do
      [{^type, module}] -> {:ok, module}
      [] -> {:error, :unknown_type}
    end
  end

  @spec list() :: [type_name()]
  def list do
    @table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {:__active__, _} -> []
      {type, _module} -> [type]
    end)
    |> Enum.sort()
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:register, type, module}, _from, state) do
    :ets.insert(@table, {type, module})
    {:reply, :ok, state}
  end

  def handle_call({:set_active, type}, _from, state) do
    :ets.insert(@table, {:__active__, type})
    {:reply, :ok, state}
  end

  defp unwrap_active({:ok, module}), do: {:ok, module}
  defp unwrap_active({:error, :unknown_type}), do: {:error, :no_active_adapter}
end
