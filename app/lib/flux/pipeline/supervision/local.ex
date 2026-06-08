defmodule Flux.Pipeline.Supervision.Local do
  @moduledoc """
  Single-node pipeline supervision for the Community edition.

  Backed by a plain `Registry` (`:unique`) and `DynamicSupervisor`, both started
  in `Flux.Application` under the names below. Runners live on this node only —
  there is no clustering. The Pro build overrides the `Flux.Pipeline.Supervision`
  implementation with a Horde-backed distributed version.

  The unique registry preserves the "a pipeline runs at most once" invariant on
  this node: a duplicate start registering the same `{:runner, id}` name fails
  with `{:already_started, pid}`, which `start_pipeline/1` treats as success.
  """

  @behaviour Flux.Pipeline.Supervision

  @registry Flux.Pipeline.Registry
  @supervisor Flux.Pipeline.DynamicSupervisor

  @impl true
  def via_tuple(pipeline_id) do
    {:via, Registry, {@registry, {:runner, pipeline_id}}}
  end

  @impl true
  def child_via({:via, Registry, {registry, key}}, base_name) do
    {:via, Registry, {registry, {key, base_name}}}
  end

  @impl true
  def start_pipeline(child_spec) do
    case DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def terminate_pipeline(pid) do
    DynamicSupervisor.terminate_child(@supervisor, pid)
  end

  @impl true
  def whereis(pipeline_id) do
    case Registry.lookup(@registry, {:runner, pipeline_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @impl true
  def list_running do
    @registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn
      {:runner, id} -> [id]
      _ -> []
    end)
    |> Enum.uniq()
  end

  @impl true
  def member_count, do: 1

  @impl true
  def ready?, do: true
end
