defmodule Flux.QueueTest do
  use ExUnit.Case, async: true

  alias Flux.Queue
  alias Flux.Queue.Message

  describe "adapter/0" do
    test "returns configured adapter" do
      assert Queue.adapter() == Flux.Queue.Adapters.Memory
    end
  end

  describe "publish/3" do
    test "delegates to the configured adapter without crashing" do
      message = Message.new(%{event: "test"}, source: "test")
      assert :ok = Queue.publish("test_queue", message)
    end
  end

  describe "ack/1" do
    test "delegates to the configured adapter without crashing" do
      message = Message.new(%{event: "test"}, source: "test")
      :ok = Queue.publish("test_queue", message)
      assert :ok = Queue.ack(message)
    end
  end

  describe "reject/2" do
    test "delegates to the configured adapter without crashing" do
      message = Message.new(%{event: "test"}, source: "test")
      :ok = Queue.publish("test_queue", message)
      assert :ok = Queue.reject(message, false)
    end

    test "reject with requeue delegates without crashing" do
      message = Message.new(%{event: "test"}, source: "test")
      :ok = Queue.publish("test_queue", message)
      assert :ok = Queue.reject(message, true)
    end
  end

  describe "DLQ facade with an adapter that omits the optional callbacks" do
    # The active adapter in test is Memory, which does not implement the DLQ
    # callbacks. The facade must return a clean upgrade error, not crash.
    test "list_dlq_messages/2 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.list_dlq_messages()
      assert {:error, {:pro_required, :dlq}} = Queue.list_dlq_messages(10, 5)
    end

    test "dlq_depth/0 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.dlq_depth()
    end

    test "retry_message/1 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.retry_message(1)
    end

    test "discard_message/1 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.discard_message(1)
    end

    test "replay_dlq/2 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.replay_dlq(%{}, 100)
    end
  end
end
