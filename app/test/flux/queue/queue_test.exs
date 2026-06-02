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
end
