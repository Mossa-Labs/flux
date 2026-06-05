defmodule Flux.Pipeline.Manager do
  @moduledoc """
  Manages pipeline lifecycle: starting, stopping, pausing, and resuming pipelines.

  On application boot, automatically starts all pipelines with status "active".
  """

  use GenServer

  alias Flux.Pipelines
  alias Flux.Pipeline.Runner

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a pipeline by ID.

  The pipeline must exist in the database and not already be running.
  """
  def start_pipeline(pipeline_id) do
    GenServer.call(__MODULE__, {:start_pipeline, pipeline_id})
  end

  @doc """
  Stops a running pipeline by ID.
  """
  def stop_pipeline(pipeline_id) do
    GenServer.call(__MODULE__, {:stop_pipeline, pipeline_id})
  end

  @doc """
  Gets the status of a pipeline.

  Returns `:running`, `:stopped`, or `:not_found`.
  """
  def get_status(pipeline_id) do
    case Horde.Registry.lookup(Flux.Pipeline.Registry, {:runner, pipeline_id}) do
      [{_pid, _}] -> :running
      [] -> :stopped
    end
  end

  @doc """
  Lists all currently running pipeline IDs (cluster-wide).
  """
  def list_running do
    Horde.Registry.select(Flux.Pipeline.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.filter(fn
      {:runner, _id} -> true
      _ -> false
    end)
    |> Enum.map(fn {:runner, id} -> id end)
    |> Enum.uniq()
  end

  @impl true
  def init(_opts) do
    send(self(), :auto_start)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:auto_start, state) do
    Logger.info("Pipeline Manager: Auto-starting active pipelines...")

    pipelines = Pipelines.list_active_pipelines()

    for pipeline <- pipelines do
      case do_start_pipeline(pipeline) do
        {:ok, _pid} ->
          Logger.info("Pipeline Manager: Started pipeline #{pipeline.id} (#{pipeline.name})")

        {:error, reason} ->
          Logger.error(
            "Pipeline Manager: Failed to start pipeline #{pipeline.id}: #{inspect(reason)}"
          )
      end
    end

    Logger.info(
      "Pipeline Manager: Auto-start complete. #{length(pipelines)} pipeline(s) started."
    )

    {:noreply, state}
  end

  @impl true
  def handle_call({:start_pipeline, pipeline_id}, _from, state) do
    result =
      case get_status(pipeline_id) do
        :running ->
          {:error, :already_running}

        :stopped ->
          case Pipelines.get_pipeline!(pipeline_id) do
            nil ->
              {:error, :not_found}

            pipeline ->
              case do_start_pipeline(pipeline) do
                {:ok, pid} ->
                  Pipelines.update_status(pipeline, "active")
                  {:ok, pid}

                {:error, reason} ->
                  {:error, reason}
              end
          end
      end

    {:reply, result, state}
  rescue
    Ecto.NoResultsError ->
      {:reply, {:error, :not_found}, state}
  end

  @impl true
  def handle_call({:stop_pipeline, pipeline_id}, _from, state) do
    result =
      case Horde.Registry.lookup(Flux.Pipeline.Registry, {:runner, pipeline_id}) do
        [{pid, _}] ->
          Horde.DynamicSupervisor.terminate_child(Flux.Pipeline.DynamicSupervisor, pid)

          case Pipelines.get_pipeline!(pipeline_id) do
            nil -> :ok
            pipeline -> Pipelines.update_status(pipeline, "stopped")
          end

          :ok

        [] ->
          {:error, :not_running}
      end

    {:reply, result, state}
  rescue
    Ecto.NoResultsError ->
      {:reply, :ok, state}
  end

  defp do_start_pipeline(pipeline) do
    child_spec = Runner.child_spec(pipeline)

    # Horde.DynamicSupervisor places the runner on one cluster node; the unique
    # Horde.Registry name makes a concurrent start on another node return
    # {:already_started, pid}, which we treat as success (idempotent auto-start).
    case Horde.DynamicSupervisor.start_child(Flux.Pipeline.DynamicSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
