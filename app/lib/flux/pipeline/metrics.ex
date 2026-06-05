defmodule Flux.Pipeline.Metrics do
  @moduledoc """
  In-memory metrics aggregator for pipeline telemetry.

  Subscribes to telemetry events and maintains rolling counters for
  throughput, error rates, and per-pipeline statistics. Broadcasts
  periodic updates via PubSub for LiveView consumption.
  """

  use GenServer

  @pubsub_topic "pipeline_metrics"
  @broadcast_interval_ms 2_000
  @window_seconds 60

  # -- Public API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns a snapshot of current metrics."
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc "Returns the PubSub topic for metrics updates."
  def topic, do: @pubsub_topic

  @doc """
  Folds per-node metric maps into cluster-wide totals. Each node broadcasts its
  own local counters (tagged with `:node`); the dashboard sums them so totals
  reflect the whole cluster regardless of which node serves the LiveView.
  """
  def fold(node_metrics) when is_list(node_metrics) do
    Enum.reduce(
      node_metrics,
      %{events_per_sec: 0.0, processed_total: 0, failed_total: 0},
      fn m, acc ->
        %{
          events_per_sec: acc.events_per_sec + (Map.get(m, :events_per_sec) || 0),
          processed_total: acc.processed_total + (Map.get(m, :processed_total) || 0),
          failed_total: acc.failed_total + (Map.get(m, :failed_total) || 0)
        }
      end
    )
  end

  # -- GenServer callbacks --

  @impl true
  def init(_opts) do
    attach_telemetry_handlers()
    schedule_broadcast()

    {:ok,
     %{
       processed_total: 0,
       failed_total: 0,
       skipped_total: 0,
       recent_timestamps: :queue.new(),
       per_pipeline: %{}
     }}
  end

  @impl true
  def handle_cast({:record_processed, pipeline_id, duration}, state) do
    now = System.monotonic_time(:millisecond)

    new_state =
      state
      |> Map.update!(:processed_total, &(&1 + 1))
      |> Map.update!(:recent_timestamps, &:queue.in(now, &1))
      |> update_pipeline_metric(pipeline_id, :processed, duration)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failed, pipeline_id}, state) do
    new_state =
      state
      |> Map.update!(:failed_total, &(&1 + 1))
      |> update_pipeline_metric(pipeline_id, :failed, 0)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_skipped, pipeline_id}, state) do
    new_state =
      state
      |> Map.update!(:skipped_total, &(&1 + 1))
      |> update_pipeline_metric(pipeline_id, :skipped, 0)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    now = System.monotonic_time(:millisecond)
    events_per_sec = calculate_throughput(state.recent_timestamps, now)

    snapshot = %{
      processed_total: state.processed_total,
      failed_total: state.failed_total,
      skipped_total: state.skipped_total,
      events_per_sec: events_per_sec,
      per_pipeline: state.per_pipeline
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_info(:broadcast, state) do
    now = System.monotonic_time(:millisecond)
    events_per_sec = calculate_throughput(state.recent_timestamps, now)
    pruned = prune_queue(state.recent_timestamps, now)

    Phoenix.PubSub.broadcast(
      Flux.PubSub,
      @pubsub_topic,
      {:metrics_update,
       %{
         node: node(),
         events_per_sec: events_per_sec,
         processed_total: state.processed_total,
         failed_total: state.failed_total,
         skipped_total: state.skipped_total
       }}
    )

    schedule_broadcast()
    {:noreply, %{state | recent_timestamps: pruned}}
  end

  # -- Private --

  defp attach_telemetry_handlers do
    :telemetry.attach(
      "flux-metrics-processed",
      [:flux, :pipeline, :message, :processed],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    :telemetry.attach(
      "flux-metrics-failed",
      [:flux, :pipeline, :message, :failed],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    :telemetry.attach(
      "flux-metrics-skipped",
      [:flux, :pipeline, :message, :skipped],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )
  end

  @doc false
  def handle_telemetry_event(
        [:flux, :pipeline, :message, :processed],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_processed, metadata.pipeline_id, measurements.duration})
  end

  def handle_telemetry_event(
        [:flux, :pipeline, :message, :failed],
        _measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_failed, metadata.pipeline_id})
  end

  def handle_telemetry_event(
        [:flux, :pipeline, :message, :skipped],
        _measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_skipped, metadata.pipeline_id})
  end

  defp schedule_broadcast do
    Process.send_after(self(), :broadcast, @broadcast_interval_ms)
  end

  defp calculate_throughput(queue, now) do
    cutoff = now - @window_seconds * 1_000
    count = :queue.fold(fn ts, acc -> if ts >= cutoff, do: acc + 1, else: acc end, 0, queue)
    Float.round(count / @window_seconds, 1)
  end

  defp prune_queue(queue, now) do
    cutoff = now - @window_seconds * 1_000
    :queue.filter(fn ts -> ts >= cutoff end, queue)
  end

  defp update_pipeline_metric(state, pipeline_id, type, duration) do
    default = %{processed: 0, failed: 0, skipped: 0, total_duration: 0}
    pipeline_metrics = Map.get(state.per_pipeline, pipeline_id, default)

    updated =
      pipeline_metrics
      |> Map.update!(type, &(&1 + 1))
      |> then(fn m ->
        if type == :processed, do: Map.update!(m, :total_duration, &(&1 + duration)), else: m
      end)

    %{state | per_pipeline: Map.put(state.per_pipeline, pipeline_id, updated)}
  end
end
