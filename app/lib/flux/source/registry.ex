defmodule Flux.Source.Registry do
  @moduledoc """
  Runtime lookup table for source adapters.

  Community adapters (Webhook, Poll) self-register at boot from
  `Flux.Registrations`. The commercial edition registers its own adapters
  (Kafka, ...) at boot, replacing the Community stub.

  The table is an ETS-backed keyed map; reads are lock-free. Mirrors
  `Flux.Sink.Registry`.
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

  @spec lookup(type_name() | atom()) :: {:ok, module()} | {:error, :unknown_type}
  def lookup(type) when is_atom(type), do: lookup(Atom.to_string(type))

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
    |> Enum.map(fn {type, _module} -> type end)
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
end
