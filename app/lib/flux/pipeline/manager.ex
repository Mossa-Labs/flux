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
        # A failed query here (the DB is still starting, or — in tests — this
        # process owns no sandbox connection) must NOT crash the Manager: a
        # crash-loop would exceed the supervisor's restart intensity and take
        # the whole app down with it (Repo, Endpoint, ...). Retry instead.
        case run_auto_start() do
          :ok -> {:noreply, state}
          :error -> retry_auto_start(state)
        end

      state.auto_start_attempts >= @auto_start_max_attempts ->
        Logger.error(
          "Pipeline Manager: supervision backend not ready after " <>
            "#{@auto_start_max_attempts} attempts; auto-starting anyway."
        )

        run_auto_start()
        {:noreply, state}

      true ->
        retry_auto_start(state)
    end
  end

  defp retry_auto_start(state) do
    if state.auto_start_attempts >= @auto_start_max_attempts do
      Logger.error(
        "Pipeline Manager: gave up auto-starting active pipelines after " <>
          "#{@auto_start_max_attempts} attempts (database unavailable)."
      )

      {:noreply, state}
    else
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

    :ok
  rescue
    error ->
      Logger.warning("Pipeline Manager: auto-start deferred — #{Exception.message(error)}")
      :error
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
              # Abuse-protection safety valve (MOS-450): cap user-initiated
              # starts per org and node-wide. Auto-start bypasses this path
              # (run_auto_start/0 calls do_start_pipeline/1 directly), so the
              # boot path is never throttled.
              if within_start_limits?(pipeline.organization_id) do
                case do_start_pipeline(pipeline) do
                  {:ok, pid} ->
                    Pipelines.update_status(pipeline, "active")
                    {:ok, pid}

                  {:error, reason} ->
                    {:error, reason}
                end
              else
                {:error, :rate_limited}
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

  # Per-org fairness + a node-wide ceiling on user-initiated pipeline starts.
  # Short-circuit `and`: a per-org denial never consumes a node-ceiling token.
  defp within_start_limits?(org_id) do
    {limit, node_limit, window_ms} = start_limit_config()

    Flux.RateLimiter.allow?({:pipeline_start, org_id}, limit, window_ms) and
      Flux.RateLimiter.allow?(:pipeline_start_node, node_limit, window_ms)
  end

  defp start_limit_config do
    opts = Application.get_env(:flux, __MODULE__, [])

    {
      Keyword.get(opts, :start_limit, 20),
      Keyword.get(opts, :start_node_limit, 100),
      Keyword.get(opts, :start_window_ms, 60_000)
    }
  end
end
