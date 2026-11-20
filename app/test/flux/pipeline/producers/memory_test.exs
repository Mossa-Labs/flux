defmodule Flux.Pipeline.Producers.MemoryTest do
  use ExUnit.Case, async: false

  alias Flux.Pipeline.Producers.Memory

  # Minimal GenStage consumer that forwards received events to a test process so
  # we can observe what the producer dispatches under demand.
  defmodule Collector do
    use GenStage

    def start_link({producer, test_pid}) do
      GenStage.start_link(__MODULE__, {producer, test_pid})
    end

    @impl true
    def init({producer, test_pid}) do
      {:consumer, test_pid, subscribe_to: [{producer, max_demand: 5}]}
    end

    @impl true
    def handle_events(events, _from, test_pid) do
      for event <- events, do: send(test_pid, {:event, event.data, event.metadata})
      {:noreply, [], test_pid}
    end
  end

  @org 42

  # The producer consumes a physical queue, the way `Flux.Queue.producer_spec/3`
  # starts it.
  defp start_producer(logical_queue, org \\ @org) do
    start_supervised!(
      {Memory,
       [
         pipeline_id: "p-#{System.unique_integer([:positive])}",
         source_queue: Flux.Queue.Naming.physical!(org, logical_queue)
       ]}
    )
  end

  describe "push_message/3 and dispatch under demand" do
    test "a pushed message is delivered to a subscribed consumer, tagged with its organization" do
      queue = "mem.queue.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)
      start_supervised!({Collector, {producer, self()}})

      Memory.push_message(@org, queue, %{"event" => "push"})

      assert_receive {:event, %{"event" => "push"}, %{organization_id: @org}}, 1_000
    end

    test "another organization's queue of the same name is never received" do
      queue = "mem.shared.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)
      start_supervised!({Collector, {producer, self()}})

      Memory.push_message(@org + 1, queue, %{"n" => "foreign"})
      Memory.push_message(@org, queue, %{"n" => "own"})

      assert_receive {:event, %{"n" => "own"}, _}, 1_000
      refute_received {:event, %{"n" => "foreign"}, _}
    end

    test "messages buffered before demand are delivered in FIFO order" do
      queue = "mem.fifo.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)

      # Push before any consumer subscribes — these buffer in the producer's queue.
      Memory.push_message(@org, queue, %{"n" => 1})
      Memory.push_message(@org, queue, %{"n" => 2})
      Memory.push_message(@org, queue, %{"n" => 3})

      start_supervised!({Collector, {producer, self()}})

      assert_receive {:event, %{"n" => 1}, _}, 1_000
      assert_receive {:event, %{"n" => 2}, _}, 1_000
      assert_receive {:event, %{"n" => 3}, _}, 1_000
    end

    test "only messages for the producer's own queue are received" do
      queue = "mem.mine.#{System.unique_integer([:positive])}"
      other = "mem.other.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)
      start_supervised!({Collector, {producer, self()}})

      Memory.push_message(@org, other, %{"n" => "wrong"})
      Memory.push_message(@org, queue, %{"n" => "right"})

      assert_receive {:event, %{"n" => "right"}, _}, 1_000
      refute_received {:event, %{"n" => "wrong"}, _}
    end
  end

  describe "deliver/2" do
    test "delivers a published message tagged with its organization and id" do
      queue = "mem.deliver.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)
      start_supervised!({Collector, {producer, self()}})

      message = Flux.Queue.Message.new(%{"a" => 1}, source: "t", organization_id: @org)
      Memory.deliver(Flux.Queue.Naming.physical!(@org, queue), message)

      assert_receive {:event, %{"a" => 1}, metadata}, 1_000
      assert metadata == %{organization_id: @org, message_id: message.id}
    end
  end

  describe "handle_info/2" do
    test "ignores unknown messages without crashing" do
      queue = "mem.info.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)

      send(producer, :some_unexpected_message)

      # Still alive and still functioning.
      ref = Process.monitor(producer)
      refute_receive {:DOWN, ^ref, :process, ^producer, _}, 200
    end
  end

  describe "ack/3" do
    test "returns :ok" do
      assert Memory.ack(:ack_ref, [:msg], []) == :ok
    end
  end
end
