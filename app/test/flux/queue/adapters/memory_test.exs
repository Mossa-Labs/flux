defmodule Flux.Queue.Adapters.MemoryTest do
  use ExUnit.Case, async: false

  alias Flux.Queue.Adapters.Memory
  alias Flux.Queue.Message

  setup do
    # Clear the memory adapter before each test
    Memory.clear()
    :ok
  end

  describe "publish/3" do
    test "stores message in queue" do
      message = Message.new(%{test: "data"}, source: "test")

      assert :ok = Memory.publish("test_queue", message)

      messages = Memory.get_messages("test_queue")
      assert length(messages) == 1
      assert hd(messages).payload == %{test: "data"}
    end

    test "supports multiple queues" do
      msg1 = Message.new(%{queue: 1}, source: "test")
      msg2 = Message.new(%{queue: 2}, source: "test")

      Memory.publish("queue_1", msg1)
      Memory.publish("queue_2", msg2)

      assert length(Memory.get_messages("queue_1")) == 1
      assert length(Memory.get_messages("queue_2")) == 1
    end

    test "preserves message order" do
      for i <- 1..5 do
        Memory.publish("ordered", Message.new(%{order: i}, source: "test"))
      end

      messages = Memory.get_messages("ordered")
      orders = Enum.map(messages, & &1.payload.order)

      assert orders == [1, 2, 3, 4, 5]
    end

    test "accepts atom queue names" do
      message = Message.new(%{test: true}, source: "test")

      assert :ok = Memory.publish(:atom_queue, message)

      messages = Memory.get_messages(:atom_queue)
      assert length(messages) == 1
    end
  end

  describe "ack/1" do
    test "removes message from pending" do
      message = Message.new(%{test: "data"}, source: "test")
      Memory.publish("test_queue", message)

      assert :ok = Memory.ack(message)
    end
  end

  describe "reject/2" do
    test "with requeue=true moves message back to queue" do
      message = Message.new(%{test: "data"}, source: "test")
      Memory.publish("test_queue", message)

      assert :ok = Memory.reject(message, true)

      # Should still be in queue after requeue (original + requeued)
      messages = Memory.get_messages("test_queue")
      assert length(messages) == 2
    end

    test "with requeue=false discards message" do
      message = Message.new(%{test: "data"}, source: "test")
      Memory.publish("test_queue", message)

      assert :ok = Memory.reject(message, false)
    end

    test "reject unknown message with requeue returns error" do
      message = Message.new(%{unknown: true}, source: "test")

      assert {:error, :not_found} = Memory.reject(message, true)
    end
  end

  describe "get_messages/1" do
    test "returns empty list for unknown queue" do
      assert Memory.get_messages("nonexistent") == []
    end
  end

  describe "clear/0" do
    test "removes all messages from all queues" do
      Memory.publish("queue_1", Message.new(%{a: 1}, source: "test"))
      Memory.publish("queue_2", Message.new(%{b: 2}, source: "test"))

      Memory.clear()

      assert Memory.get_messages("queue_1") == []
      assert Memory.get_messages("queue_2") == []
    end
  end
end
