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
    Broadway.start_link(__MODULE__,
      name: via_tuple(pipeline.id),
      producer: producer_config(pipeline),
      processors: processors_config(pipeline),
      context: %{
        pipeline_id: pipeline.id,
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
  def process_name({:via, Registry, {registry, key}}, base_name) do
    {:via, Registry, {registry, {key, base_name}}}
  end

  defp via_tuple(pipeline_id) do
    {:via, Registry, {Flux.Pipeline.Registry, {:runner, pipeline_id}}}
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

  defp processors_config(pipeline) do
    config = Map.get(pipeline.config, "processors", %{})
    concurrency = Map.get(config, "concurrency", 10)

    [default: [concurrency: concurrency]]
  end

  @impl true
  def handle_message(_processor, %Message{data: data} = message, context) do
    %{
      pipeline_id: pipeline_id,
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
          %{pipeline_id: pipeline_id}
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
          %{pipeline_id: pipeline_id}
        )

        Logger.debug("Message skipped in pipeline #{pipeline_id}: #{inspect(reason)}")

        message
        |> Message.put_data(nil)
        |> Message.ack_immediately()

      {:error, reason} ->
        :telemetry.execute(
          [:flux, :pipeline, :message, :failed],
          %{count: 1},
          %{pipeline_id: pipeline_id}
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

  defp record_metrics(pipeline_id, data) when is_map(data) do
    for {key, value} <- data, is_number(value) do
      Flux.AI.record(pipeline_id, key, value)
    end

    :ok
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
            :ok

          {:ok, _meta} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "Sink #{sink.id} (#{sink.name}) delivery failed for pipeline #{pipeline_id}: #{inspect(reason)}"
            )
        end
      end)
    end

    :ok
  end
end
