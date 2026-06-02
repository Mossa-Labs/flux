defmodule Flux.Pipeline.Producers.Memory do
  @moduledoc """
  In-memory Broadway producer for development and testing.

  Subscribes to Phoenix PubSub to receive messages for the pipeline's source queue.
  Messages are pushed via `push_message/2`.

  ## Usage

      # Push a message to a pipeline's source queue
      Flux.Pipeline.Producers.Memory.push_message("webhooks.github", %{event: "push"})
  """

  use GenStage

  require Logger

  @doc """
  Pushes a message to all producers listening on the given source queue.
  """
  def push_message(source_queue, data) do
    Phoenix.PubSub.broadcast(Flux.PubSub, "pipeline:#{source_queue}", {:message, data})
  end

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    pipeline_id = Keyword.fetch!(opts, :pipeline_id)
    source_queue = Keyword.fetch!(opts, :source_queue)

    Phoenix.PubSub.subscribe(Flux.PubSub, "pipeline:#{source_queue}")

    Logger.debug("Memory producer started for pipeline #{pipeline_id}, queue: #{source_queue}")

    {:producer,
     %{pipeline_id: pipeline_id, source_queue: source_queue, queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    dispatch_events(state, incoming_demand + state.demand)
  end

  @impl true
  def handle_info({:message, data}, state) do
    message = %Broadway.Message{
      data: data,
      acknowledger: {__MODULE__, :ack_ref, :ok}
    }

    new_queue = :queue.in(message, state.queue)
    dispatch_events(%{state | queue: new_queue}, state.demand)
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  defp dispatch_events(state, 0) do
    {:noreply, [], %{state | demand: 0}}
  end

  defp dispatch_events(state, demand) do
    {events, new_queue, remaining_demand} = take_events(state.queue, demand, [])
    {:noreply, Enum.reverse(events), %{state | queue: new_queue, demand: remaining_demand}}
  end

  defp take_events(queue, 0, acc) do
    {acc, queue, 0}
  end

  defp take_events(queue, demand, acc) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        take_events(new_queue, demand - 1, [event | acc])

      {:empty, queue} ->
        {acc, queue, demand}
    end
  end

  @doc false
  def ack(:ack_ref, _successful, _failed) do
    :ok
  end
end
