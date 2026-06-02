defmodule Flux.Pipeline.StepRegistry do
  @moduledoc """
  Runtime lookup table for pipeline step modules.

  Community steps (map, filter, rename) self-register at boot; the commercial
  edition adds Pro step types (advanced AI, enrichment, etc.) at boot.
  """

  use GenServer

  @table __MODULE__

  @type operation :: String.t()

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec register(operation(), module()) :: :ok
  def register(operation, module) when is_binary(operation) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, operation, module})
  end

  @spec lookup(operation()) :: {:ok, module()} | {:error, String.t()}
  def lookup(operation) when is_binary(operation) do
    case :ets.lookup(@table, operation) do
      [{^operation, module}] -> {:ok, module}
      [] -> {:error, "Unknown operation: #{operation}"}
    end
  end

  @spec list() :: [operation()]
  def list do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {op, _module} -> op end)
    |> Enum.sort()
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:register, operation, module}, _from, state) do
    :ets.insert(@table, {operation, module})
    {:reply, :ok, state}
  end
end
