defmodule Flux.Auth.Registry do
  @moduledoc """
  Runtime lookup table for authentication strategy modules.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec register(atom(), module()) :: :ok
  def register(name, module) when is_atom(name) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, name, module})
  end

  @spec lookup(atom()) :: {:ok, module()} | {:error, :unknown_strategy}
  def lookup(name) when is_atom(name) do
    case :ets.lookup(@table, name) do
      [{^name, module}] -> {:ok, module}
      [] -> {:error, :unknown_strategy}
    end
  end

  @spec list() :: [atom()]
  def list do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {name, _module} -> name end)
    |> Enum.sort()
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:register, name, module}, _from, state) do
    :ets.insert(@table, {name, module})
    {:reply, :ok, state}
  end
end
