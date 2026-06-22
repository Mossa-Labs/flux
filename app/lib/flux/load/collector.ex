defmodule Flux.Load.Collector do
  @moduledoc """
  Per-run telemetry collector for the load harness.

  Attaches to the pipeline telemetry events and records per-message processing
  latency plus processed/failed/skipped/sink-delivered counts. Unlike
  `Flux.Pipeline.Metrics` (which only sums durations), this keeps individual
  latency samples so percentiles can be computed by `Flux.Load.Stats`.

  Pass `:pipeline_ids` to scope collection to one run's pipelines; omit it (or
  pass `:all`) to aggregate across every pipeline. Latency samples are capped at
  `:sample_cap` (default 200k) to bound memory on million-message runs — counts
  always stay exact.

  Mirrors the `:telemetry.attach` + `GenServer.cast` pattern used by
  `Flux.Pipeline.Metrics` to keep the telemetry hot path off the mailbox.
  """

  use GenServer

  @processed [:flux, :pipeline, :message, :processed]
  @failed [:flux, :pipeline, :message, :failed]
  @skipped [:flux, :pipeline, :message, :skipped]
  @delivered [:flux, :sink, :delivered]

  @default_sample_cap 200_000

  # -- Public API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns `%{durations, processed, failed, skipped, sink_delivered}`."
  def flush(pid), do: GenServer.call(pid, :flush)

  def stop(pid), do: GenServer.stop(pid)

  # -- GenServer callbacks --

  @impl true
  def init(opts) do
    filter =
      case Keyword.get(opts, :pipeline_ids, :all) do
        :all -> :all
        ids when is_list(ids) -> MapSet.new(ids)
      end

    handler_id = "flux-load-collector-#{System.unique_integer([:positive])}"
    events = [@processed, @failed, @skipped, @delivered]
    :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, self())

    {:ok,
     %{
       filter: filter,
       handler_id: handler_id,
       sample_cap: Keyword.get(opts, :sample_cap, @default_sample_cap),
       durations: [],
       sampled: 0,
       processed: 0,
       failed: 0,
       skipped: 0,
       sink_delivered: 0
     }}
  end

  @doc false
  def handle_event(event, measurements, metadata, pid) do
    GenServer.cast(pid, {:event, event, measurements, metadata})
  end

  @impl true
  def handle_cast({:event, event, measurements, metadata}, state) do
    if relevant?(state.filter, metadata) do
      {:noreply, record(state, event, measurements)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply,
     %{
       durations: state.durations,
       processed: state.processed,
       failed: state.failed,
       skipped: state.skipped,
       sink_delivered: state.sink_delivered
     }, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  # -- Private --

  defp relevant?(:all, _metadata), do: true
  defp relevant?(filter, %{pipeline_id: id}), do: MapSet.member?(filter, id)
  defp relevant?(_filter, _metadata), do: false

  defp record(state, @processed, %{duration: duration}) do
    state = %{state | processed: state.processed + 1}

    if state.sampled < state.sample_cap do
      us = System.convert_time_unit(duration, :native, :microsecond)
      %{state | durations: [us | state.durations], sampled: state.sampled + 1}
    else
      state
    end
  end

  defp record(state, @failed, _measurements), do: %{state | failed: state.failed + 1}
  defp record(state, @skipped, _measurements), do: %{state | skipped: state.skipped + 1}

  defp record(state, @delivered, _measurements),
    do: %{state | sink_delivered: state.sink_delivered + 1}

  defp record(state, _event, _measurements), do: state
end
