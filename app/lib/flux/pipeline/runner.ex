defmodule Flux.Pipeline.Runner do
  @moduledoc """
  Broadway-based pipeline runner for processing messages through transformation steps.

  Each pipeline instance is a separate Broadway process that:
  1. Consumes messages from a source queue
  2. Applies transformation steps via the Interpreter
  3. Optionally publishes results to a destination queue
  4. Records metrics to the AI Detector

  ## Configuration

  The pipeline config supports:
  - `producer.concurrency`: Number of producer processes (default: 1)
  - `processors.concurrency`: Number of processor processes (default: 10)
  """

  use Broadway

  alias Broadway.Message
  alias Flux.Pipeline.Interpreter
  alias Flux.Pipelines.Pipeline

  require Logger

  @doc """
  Starts a Broadway pipeline for the given pipeline configuration.
  """
  def start_link(%Pipeline{} = pipeline) do
    configure_detector(pipeline)

    Broadway.start_link(__MODULE__,
      name: via_tuple(pipeline.id),
      producer: producer_config(pipeline),
      processors: processors_config(pipeline),
      context: %{
        pipeline_id: pipeline.id,
        version: pipeline.current_version,
        steps: pipeline.steps,
        destination_queue: pipeline.destination_queue,
        sink_ids: pipeline.sink_ids || []
      }
    )
  end

  def child_spec(%Pipeline{} = pipeline) do
    %{
      id: {__MODULE__, pipeline.id},
      start: {__MODULE__, :start_link, [pipeline]},
      restart: :permanent,
      type: :supervisor
    }
  end

  @impl true
  def process_name(via, base_name) do
    Flux.Pipeline.Supervision.child_via(via, base_name)
  end

  # Unique runner name resolved through the active supervision backend (local
  # Registry for Community; cluster-wide Horde.Registry for Pro). The unique name
  # makes a duplicate start return {:already_started, pid}, so each pipeline runs once.
  defp via_tuple(pipeline_id) do
    Flux.Pipeline.Supervision.via_tuple(pipeline_id)
  end

  defp producer_config(pipeline) do
    producer = Map.get(pipeline.config, "producer", %{})
    concurrency = Map.get(producer, "concurrency", 1)
    source_config = extract_source_config(pipeline)
    queue = source_config["queue"] || pipeline.source_queue
    prefetch_count = source_config["prefetchCount"] || 50

    {:ok, adapter} = Flux.Queue.Registry.active()

    spec_opts = [pipeline_id: pipeline.id, queue: queue, prefetch_count: prefetch_count]

    [module: adapter.producer_spec(spec_opts), concurrency: concurrency]
  end

  defp extract_source_config(pipeline) do
    case pipeline.steps do
      %{"nodes" => nodes} when is_list(nodes) ->
        source_nodes = Enum.filter(nodes, fn n -> n["type"] == "source" end)

        if length(source_nodes) > 1 do
          Logger.warning(
            "Pipeline #{pipeline.id} has #{length(source_nodes)} source nodes. " <>
              "Using first source node. Multi-source execution is not yet supported."
          )
        end

        case List.first(source_nodes) do
          %{"sourceConfig" => config} when is_map(config) -> config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  # Registers this pipeline's anomaly-detection mode with the active AI provider
  # once at startup, so record-time ingestion and score-time dispatch know the mode
  # without re-reading the step config on the hot path. No-op when there is no
  # `anomaly_detect` step or the active provider is the Community stub.
  defp configure_detector(pipeline) do
    case extract_ai_config(pipeline) do
      nil ->
        :ok

      config ->
        mode = mode_atom(Map.get(config, "mode", "numeric"))
        Flux.AI.configure(pipeline.id, mode, mode_params(config))
    end
  end

  # Mode-specific params, normalized from the (flat, string-valued) step config the
  # builder produces. `fields` is parsed from its comma-separated form into a list.
  defp mode_params(config) do
    %{
      "fields" => parse_fields(Map.get(config, "fields")),
      "period" => Map.get(config, "period"),
      "smoothing" => Map.get(config, "smoothing"),
      "algorithm" => Map.get(config, "algorithm"),
      "alpha" => Map.get(config, "alpha"),
      "beta" => Map.get(config, "beta"),
      "gamma" => Map.get(config, "gamma"),
      "n_trees" => Map.get(config, "n_trees"),
      "subsample" => Map.get(config, "subsample")
    }
  end

  defp parse_fields(fields) when is_list(fields), do: fields

  defp parse_fields(fields) when is_binary(fields) do
    fields |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_fields(_), do: []

  # Finds the `anomaly_detect` step's config in the compiled IR (`steps["steps"]`),
  # the same config the Interpreter runs. Returns nil when absent.
  defp extract_ai_config(%Pipeline{steps: %{"steps" => steps}}) when is_list(steps) do
    Enum.find_value(steps, fn
      %{"type" => "ai", "operation" => "anomaly_detect"} = step -> Map.get(step, "config", %{})
      _ -> nil
    end)
  end

  defp extract_ai_config(_pipeline), do: nil

  defp mode_atom("seasonal"), do: :seasonal
  defp mode_atom("multivariate"), do: :multivariate
  defp mode_atom("categorical"), do: :categorical
  defp mode_atom(_), do: :numeric

  defp processors_config(pipeline) do
    config = Map.get(pipeline.config, "processors", %{})
    concurrency = Map.get(config, "concurrency", 10)

    [default: [concurrency: concurrency]]
  end

  @impl true
  def handle_message(_processor, %Message{data: data} = message, context) do
    %{
      pipeline_id: pipeline_id,
      version: version,
      steps: steps,
      destination_queue: destination_queue,
      sink_ids: sink_ids
    } = context

    parsed_data = parse_data(data)
    start_time = System.monotonic_time()

    case Interpreter.execute(parsed_data, steps) do
      {:ok, transformed_data} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:flux, :pipeline, :message, :processed],
          %{duration: duration, count: 1},
          %{pipeline_id: pipeline_id, version: version}
        )

        record_metrics(pipeline_id, transformed_data)
        maybe_publish(transformed_data, destination_queue)
        deliver_to_sinks(transformed_data, sink_ids, pipeline_id)

        message
        |> Message.put_data(transformed_data)

      {:skip, reason} ->
        :telemetry.execute(
          [:flux, :pipeline, :message, :skipped],
          %{count: 1},
          %{pipeline_id: pipeline_id, version: version}
        )

        Logger.debug("Message skipped in pipeline #{pipeline_id}: #{inspect(reason)}")

        message
        |> Message.put_data(nil)
        |> Message.ack_immediately()

      {:error, reason} ->
        :telemetry.execute(
          [:flux, :pipeline, :message, :failed],
          %{count: 1},
          %{pipeline_id: pipeline_id, version: version}
        )

        Logger.error("Message failed in pipeline #{pipeline_id}: #{inspect(reason)}")

        message
        |> Message.failed(reason)
    end
  end

  @impl true
  def handle_failed(messages, context) do
    %{pipeline_id: pipeline_id} = context

    :telemetry.execute(
      [:flux, :pipeline, :batch, :failed],
      %{count: length(messages)},
      %{pipeline_id: pipeline_id}
    )

    for message <- messages do
      Logger.error(
        "Pipeline #{pipeline_id} failed to process message: #{inspect(message.data)}, " <>
          "reason: #{inspect(message.status)}"
      )
    end

    messages
  end

  defp parse_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"raw" => data}
    end
  end

  defp parse_data(data) when is_map(data), do: data
  defp parse_data(data), do: %{"raw" => data}

  # Hands the whole row to the active provider, which extracts what it needs based
  # on the pipeline's configured mode (numeric per-field, categorical strings, or a
  # joint multivariate vector). The Community stub no-ops; the facade falls back to
  # per-numeric-field recording for providers without `record_observation/2`.
  defp record_metrics(pipeline_id, data) when is_map(data) do
    Flux.AI.record_observation(pipeline_id, data)
  end

  defp record_metrics(_pipeline_id, _data), do: :ok

  defp maybe_publish(_data, nil), do: :ok
  defp maybe_publish(_data, ""), do: :ok

  defp maybe_publish(data, destination_queue) do
    message = Flux.Queue.Message.new(data, source: "pipeline")
    Flux.Queue.publish(destination_queue, message, [])
  end

  defp deliver_to_sinks(_data, [], _pipeline_id), do: :ok

  defp deliver_to_sinks(data, sink_ids, pipeline_id) do
    sinks = Flux.Sinks.get_sinks_by_ids(sink_ids)

    for sink <- sinks do
      Task.start(fn ->
        config = Map.put(sink.config, "type", sink.type)
        opts = [pipeline_id: pipeline_id, message_id: Ecto.UUID.generate()]

        case Flux.Sink.deliver(data, config, opts) do
          :ok ->
            emit_sink_delivered(sink, pipeline_id)

          {:ok, _meta} ->
            emit_sink_delivered(sink, pipeline_id)

          {:error, reason} ->
            Logger.error(
              "Sink #{sink.id} (#{sink.name}) delivery failed for pipeline #{pipeline_id}: #{inspect(reason)}"
            )
        end
      end)
    end

    :ok
  end

  # `sink_deliveries` hook point: a Pro metering handler attaches here and
  # resolves the organization from `pipeline_id`. Non-proprietary emit only.
  defp emit_sink_delivered(sink, pipeline_id) do
    :telemetry.execute(
      [:flux, :sink, :delivered],
      %{count: 1},
      %{pipeline_id: pipeline_id, sink_id: sink.id}
    )
  end
end
