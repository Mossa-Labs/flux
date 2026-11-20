defmodule Flux.Pipeline.Producers.Memory do
  @moduledoc """
  In-memory Broadway producer for development and testing.

  Subscribes to Phoenix PubSub to receive messages for the pipeline's physical
  source queue (see `Flux.Queue.Naming`). Every message it emits carries the
  organization it was published for in `metadata.organization_id`, which the
  runner checks against the pipeline's own organization.

  ## Usage

      # Push a message to organization 42's "webhooks.github" queue
      Flux.Pipeline.Producers.Memory.push_message(42, "webhooks.github", %{event: "push"})
  """

  use GenStage

  alias Flux.Queue.Message
  alias Flux.Queue.Naming

  require Logger

  @doc """
  Delivers a published message to every producer consuming the physical queue
  `queue`, tagged with the message's organization.
  """
  @spec deliver(String.t(), Message.t()) :: :ok | {:error, term()}
  def deliver(queue, %Message{} = message) do
    broadcast(queue, message.payload, %{
      organization_id: message.organization_id,
      message_id: message.id
    })
  end

  @doc """
  Pushes `data` to every producer consuming organization `org_id`'s logical
  queue `queue`. Used by tests and the load generator.
  """
  @spec push_message(pos_integer(), String.t(), term()) :: :ok | {:error, term()}
  def push_message(org_id, queue, data) do
    broadcast(Naming.physical!(org_id, queue), data, %{organization_id: org_id})
  end

  defp broadcast(queue, data, metadata) do
    Phoenix.PubSub.broadcast(Flux.PubSub, topic(queue), {:message, data, metadata})
  end

  defp topic(queue), do: "pipeline:#{queue}"

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    pipeline_id = Keyword.fetch!(opts, :pipeline_id)
    source_queue = Keyword.fetch!(opts, :source_queue)

    Phoenix.PubSub.subscribe(Flux.PubSub, topic(source_queue))

    Logger.debug("Memory producer started for pipeline #{pipeline_id}, queue: #{source_queue}")

    {:producer,
     %{pipeline_id: pipeline_id, source_queue: source_queue, queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    dispatch_events(state, incoming_demand + state.demand)
  end

  @impl true
  def handle_info({:message, data, metadata}, state) when is_map(metadata) do
    message = %Broadway.Message{
      data: data,
      metadata: metadata,
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
