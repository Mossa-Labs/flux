defmodule Flux.Queue.Adapters.Memory do
  @moduledoc """
  In-memory queue adapter for development and testing.

  Messages are stored in a GenServer. This adapter is NOT suitable for
  production use as messages are lost on restart.

  Queues are keyed by their physical name (see `Flux.Queue.Naming`), and a
  publish is refused unless the queue is inside the message's organization.

  ## Testing Utilities

      # Get all messages in organization 42's "my_queue" queue
      Flux.Queue.Adapters.Memory.get_messages(42, "my_queue")

      # Clear all messages (useful in test setup)
      Flux.Queue.Adapters.Memory.clear()

  """

  use GenServer

  @behaviour Flux.Queue.Adapter

  alias Flux.Queue.Message
  alias Flux.Queue.Naming

  # Client API

  @doc """
  Starts the Memory adapter GenServer.

  ## Options

    * `:name` - The name to register the process under. Defaults to `__MODULE__`.

  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl Flux.Queue.Adapter
  def publish(queue, %Message{} = message, _opts) do
    queue = to_string(queue)

    with :ok <- Naming.check_owner(queue, message.organization_id) do
      GenServer.call(__MODULE__, {:publish, queue, message})
    end
  end

  @impl Flux.Queue.Adapter
  def producer_spec(opts) do
    pipeline_id = Keyword.fetch!(opts, :pipeline_id)
    queue = Keyword.fetch!(opts, :queue)

    {Flux.Pipeline.Producers.Memory, pipeline_id: pipeline_id, source_queue: queue}
  end

  # The Memory producer tags every message it emits with the organization it
  # was published for (see `Flux.Pipeline.Producers.Memory.deliver/2`).
  @impl Flux.Queue.Adapter
  def message_organization_id(%Broadway.Message{metadata: %{organization_id: id}})
      when is_integer(id) and id > 0,
      do: {:ok, id}

  def message_organization_id(_message), do: :error

  @impl Flux.Queue.Adapter
  def ack(%Message{} = message) do
    GenServer.call(__MODULE__, {:ack, message})
  end

  @impl Flux.Queue.Adapter
  def reject(%Message{} = message, requeue \\ false) do
    GenServer.call(__MODULE__, {:reject, message, requeue})
  end

  @doc """
  Returns all messages currently in organization `org_id`'s logical queue
  `queue`.

  Messages are returned in the order they were published (oldest first).
  """
  @spec get_messages(pos_integer(), String.t()) :: [Message.t()]
  def get_messages(org_id, queue) do
    GenServer.call(__MODULE__, {:get_messages, Naming.physical!(org_id, queue)})
  end

  @doc """
  Clears all queues and pending messages.

  Useful for test setup to ensure a clean state.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %{queues: %{}, pending: %{}}}
  end

  @impl GenServer
  def handle_call({:publish, queue, message}, _from, state) do
    queues = Map.update(state.queues, queue, [message], &(&1 ++ [message]))
    pending = Map.put(state.pending, message.id, {queue, message})
    {:reply, :ok, %{state | queues: queues, pending: pending}}
  end

  def handle_call({:ack, message}, _from, state) do
    pending = Map.delete(state.pending, message.id)
    {:reply, :ok, %{state | pending: pending}}
  end

  def handle_call({:reject, message, true}, _from, state) do
    # Requeue: move back to queue
    case Map.pop(state.pending, message.id) do
      {{queue, msg}, pending} ->
        queues = Map.update(state.queues, queue, [msg], &(&1 ++ [msg]))
        {:reply, :ok, %{state | queues: queues, pending: pending}}

      {nil, _pending} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:reject, message, false}, _from, state) do
    # Discard message (no DLQ in memory adapter)
    pending = Map.delete(state.pending, message.id)
    {:reply, :ok, %{state | pending: pending}}
  end

  def handle_call({:get_messages, queue}, _from, state) do
    messages = Map.get(state.queues, queue, [])
    {:reply, messages, state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{queues: %{}, pending: %{}}}
  end
end
