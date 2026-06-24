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
      for event <- events, do: send(test_pid, {:event, event.data})
      {:noreply, [], test_pid}
    end
  end

  defp start_producer(source_queue) do
    start_supervised!(
      {Memory,
       [pipeline_id: "p-#{System.unique_integer([:positive])}", source_queue: source_queue]}
    )
  end

  describe "push_message/2 and dispatch under demand" do
    test "a pushed message is delivered to a subscribed consumer" do
      queue = "mem.queue.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)
      start_supervised!({Collector, {producer, self()}})

      Memory.push_message(queue, %{"event" => "push"})

      assert_receive {:event, %{"event" => "push"}}, 1_000
    end

    test "messages buffered before demand are delivered in FIFO order" do
      queue = "mem.fifo.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)

      # Push before any consumer subscribes — these buffer in the producer's queue.
      Memory.push_message(queue, %{"n" => 1})
      Memory.push_message(queue, %{"n" => 2})
      Memory.push_message(queue, %{"n" => 3})

      start_supervised!({Collector, {producer, self()}})

      assert_receive {:event, %{"n" => 1}}, 1_000
      assert_receive {:event, %{"n" => 2}}, 1_000
      assert_receive {:event, %{"n" => 3}}, 1_000
    end

    test "only messages for the producer's own queue are received" do
      queue = "mem.mine.#{System.unique_integer([:positive])}"
      other = "mem.other.#{System.unique_integer([:positive])}"
      producer = start_producer(queue)
      start_supervised!({Collector, {producer, self()}})

      Memory.push_message(other, %{"n" => "wrong"})
      Memory.push_message(queue, %{"n" => "right"})

      assert_receive {:event, %{"n" => "right"}}, 1_000
      refute_received {:event, %{"n" => "wrong"}}
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
