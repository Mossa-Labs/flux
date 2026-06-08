defmodule Flux.Pipeline.Manager do
  @moduledoc """
  Manages pipeline lifecycle: starting, stopping, pausing, and resuming pipelines.

  On application boot, automatically starts all pipelines with status "active".
  """

  use GenServer

  alias Flux.Pipelines
  alias Flux.Pipeline.Runner
  alias Flux.Pipeline.Supervision

  require Logger

  # Auto-start waits for the supervision backend to be ready (the distributed
  # backend's cluster infra starts after the base app). Retry with a fixed delay
  # up to a cap, then proceed regardless so a misconfiguration can't wedge boot.
  @auto_start_retry_ms 250
  @auto_start_max_attempts 40

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
    if Supervision.whereis(pipeline_id), do: :running, else: :stopped
  end

  @doc """
  Lists all currently running pipeline IDs.
  """
  def list_running do
    Supervision.list_running()
  end

  @impl true
  def init(_opts) do
    send(self(), :auto_start)
    {:ok, %{auto_start_attempts: 0}}
  end

  @impl true
  def handle_info(:auto_start, state) do
    cond do
      Supervision.ready?() ->
        run_auto_start()
        {:noreply, state}

      state.auto_start_attempts >= @auto_start_max_attempts ->
        Logger.error(
          "Pipeline Manager: supervision backend not ready after " <>
            "#{@auto_start_max_attempts} attempts; auto-starting anyway."
        )

        run_auto_start()
        {:noreply, state}

      true ->
        Process.send_after(self(), :auto_start, @auto_start_retry_ms)
        {:noreply, %{state | auto_start_attempts: state.auto_start_attempts + 1}}
    end
  end

  defp run_auto_start do
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
      case Supervision.whereis(pipeline_id) do
        pid when is_pid(pid) ->
          Supervision.terminate_pipeline(pid)

          case Pipelines.get_pipeline!(pipeline_id) do
            nil -> :ok
            pipeline -> Pipelines.update_status(pipeline, "stopped")
          end

          :ok

        nil ->
          {:error, :not_running}
      end

    {:reply, result, state}
  rescue
    Ecto.NoResultsError ->
      {:reply, :ok, state}
  end

  defp do_start_pipeline(pipeline) do
    pipeline
    |> Runner.child_spec()
    |> Supervision.start_pipeline()
  end
end
