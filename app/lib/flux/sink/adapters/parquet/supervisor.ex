defmodule Flux.Sink.Adapters.Parquet.Supervisor do
  @moduledoc """
  Hosts the Parquet sink's buffer processes: a unique `Registry` keyed by
  `{sink, pipeline}` and a `DynamicSupervisor` the buffers start under on first
  delivery.

  Started from `Flux.Application` *before* the pipeline supervisor, so on
  shutdown pipelines stop first and buffers flush last.
  """

  use Supervisor

  alias Flux.Sink.Adapters.Parquet.Buffer

  @registry Flux.Sink.Adapters.Parquet.BufferRegistry
  @buffers Flux.Sink.Adapters.Parquet.BufferSupervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @buffers, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Returns the buffer for `key`, starting it with `config` if needed."
  @spec buffer(term(), map()) :: {:ok, pid()} | {:error, term()}
  def buffer(key, config) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(@buffers, {Buffer, key: key, config: config}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "PIDs of every running buffer."
  @spec buffers() :: [pid()]
  def buffers do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(@buffers), is_pid(pid), do: pid
  end

  @doc "Stops the buffer for `key` (flushing it first). No-op if none is running."
  @spec stop_buffer(term()) :: :ok
  def stop_buffer(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] ->
        _ = DynamicSupervisor.terminate_child(@buffers, pid)
        :ok

      [] ->
        :ok
    end
  end
end
