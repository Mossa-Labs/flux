defmodule Flux.Queue.Adapters.MemoryTest do
  use ExUnit.Case, async: false

  alias Flux.Queue.Adapters.Memory
  alias Flux.Queue.Message

  @org 42

  setup do
    # Clear the memory adapter before each test
    Memory.clear()
    :ok
  end

  # The adapter receives physical queue names and stamped messages from
  # `Flux.Queue.publish/4`; these helpers build the same.
  defp message(payload, org \\ @org),
    do: Message.new(payload, source: "test", organization_id: org)

  defp queue(name, org \\ @org), do: "org.#{org}.#{name}"

  describe "publish/3" do
    test "stores message in queue" do
      assert :ok = Memory.publish(queue("test_queue"), message(%{test: "data"}), [])

      messages = Memory.get_messages(@org, "test_queue")
      assert length(messages) == 1
      assert hd(messages).payload == %{test: "data"}
    end

    test "supports multiple queues" do
      Memory.publish(queue("queue_1"), message(%{queue: 1}), [])
      Memory.publish(queue("queue_2"), message(%{queue: 2}), [])

      assert length(Memory.get_messages(@org, "queue_1")) == 1
      assert length(Memory.get_messages(@org, "queue_2")) == 1
    end

    test "keeps each organization's queue of the same name apart" do
      Memory.publish(queue("shared"), message(%{org: 42}), [])
      Memory.publish(queue("shared", 43), message(%{org: 43}, 43), [])

      assert [%{payload: %{org: 42}}] = Memory.get_messages(@org, "shared")
      assert [%{payload: %{org: 43}}] = Memory.get_messages(43, "shared")
    end

    test "preserves message order" do
      for i <- 1..5 do
        Memory.publish(queue("ordered"), message(%{order: i}), [])
      end

      messages = Memory.get_messages(@org, "ordered")
      orders = Enum.map(messages, & &1.payload.order)

      assert orders == [1, 2, 3, 4, 5]
    end

    test "refuses a queue outside the message's organization" do
      assert {:error, :organization_mismatch} =
               Memory.publish(queue("q", 43), message(%{}), [])

      assert {:error, :organization_mismatch} = Memory.publish("q", message(%{}), [])

      assert {:error, :organization_required} =
               Memory.publish(queue("q"), Message.new(%{}, source: "test"), [])

      assert Memory.get_messages(43, "q") == []
      assert Memory.get_messages(@org, "q") == []
    end
  end

  describe "message_organization_id/1" do
    test "reads the organization the Memory producer tagged" do
      tagged = %Broadway.Message{data: %{}, metadata: %{organization_id: @org}, acknowledger: nil}
      assert {:ok, @org} = Memory.message_organization_id(tagged)
    end

    test "is :error when the message carries no organization" do
      for metadata <- [%{}, %{organization_id: nil}, %{organization_id: "42"}] do
        message = %Broadway.Message{data: %{}, metadata: metadata, acknowledger: nil}
        assert :error = Memory.message_organization_id(message)
      end
    end
  end

  describe "ack/1" do
    test "removes message from pending" do
      message = message(%{test: "data"})
      Memory.publish(queue("test_queue"), message, [])

      assert :ok = Memory.ack(message)
    end
  end

  describe "reject/2" do
    test "with requeue=true moves message back to queue" do
      message = message(%{test: "data"})
      Memory.publish(queue("test_queue"), message, [])

      assert :ok = Memory.reject(message, true)

      # Should still be in queue after requeue (original + requeued)
      messages = Memory.get_messages(@org, "test_queue")
      assert length(messages) == 2
    end

    test "with requeue=false discards message" do
      message = message(%{test: "data"})
      Memory.publish(queue("test_queue"), message, [])

      assert :ok = Memory.reject(message, false)
    end

    test "reject unknown message with requeue returns error" do
      assert {:error, :not_found} = Memory.reject(message(%{unknown: true}), true)
    end
  end

  describe "get_messages/2" do
    test "returns empty list for unknown queue" do
      assert Memory.get_messages(@org, "nonexistent") == []
    end
  end

  describe "clear/0" do
    test "removes all messages from all queues" do
      Memory.publish(queue("queue_1"), message(%{a: 1}), [])
      Memory.publish(queue("queue_2"), message(%{b: 2}), [])

      Memory.clear()

      assert Memory.get_messages(@org, "queue_1") == []
      assert Memory.get_messages(@org, "queue_2") == []
    end
  end
end
