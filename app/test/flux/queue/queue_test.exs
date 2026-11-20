defmodule Flux.QueueTest do
  # async: false — the Memory adapter and the active-adapter swap are global.
  use ExUnit.Case, async: false

  alias Flux.Queue
  alias Flux.Queue.Adapters.Memory
  alias Flux.Queue.Message
  alias Flux.Queue.Registry
  alias Flux.Test.RecordingDlqQueue

  @org 42

  setup do
    Memory.clear()
    :ok
  end

  defp use_recording_adapter(_context) do
    Registry.register("recording_dlq", RecordingDlqQueue)
    Registry.set_active("recording_dlq")
    on_exit(fn -> Registry.set_active("memory") end)
    :ok
  end

  describe "adapter/0" do
    test "returns configured adapter" do
      assert Queue.adapter() == Flux.Queue.Adapters.Memory
    end
  end

  describe "publish/4" do
    test "publishes into the organization's own queue, stamped with the organization" do
      message = Message.new(%{event: "test"}, source: "test")
      assert :ok = Queue.publish(@org, "test_queue", message, [])

      assert [published] = Memory.get_messages(@org, "test_queue")
      assert published.organization_id == @org
      assert Memory.get_messages(@org + 1, "test_queue") == []
    end

    test "accepts a message already stamped with the same organization" do
      message = Message.new(%{}, source: "test", organization_id: @org)
      assert :ok = Queue.publish(@org, "test_queue", message, [])
    end

    test "refuses a missing or invalid organization" do
      message = Message.new(%{}, source: "test")

      for org <- [nil, 0, -1, "42"] do
        assert {:error, :organization_required} = Queue.publish(org, "test_queue", message, [])
      end
    end

    test "refuses a message stamped with another organization" do
      message = Message.new(%{}, source: "test", organization_id: @org + 1)

      assert {:error, :organization_mismatch} = Queue.publish(@org, "test_queue", message, [])
      assert Memory.get_messages(@org, "test_queue") == []
      assert Memory.get_messages(@org + 1, "test_queue") == []
    end

    test "refuses a queue name that can't be placed in the organization" do
      message = Message.new(%{}, source: "test")

      assert {:error, {:invalid_queue, :reserved_prefix}} =
               Queue.publish(@org, "org.7.webhooks.stripe", message, [])

      assert {:error, {:invalid_queue, :invalid_characters}} =
               Queue.publish(@org, "a b", message, [])

      assert {:error, {:invalid_queue, :blank}} = Queue.publish(@org, "", message, [])
    end
  end

  describe "producer_spec/3" do
    test "consumes the organization's physical queue" do
      assert {:ok, {Flux.Pipeline.Producers.Memory, opts}} =
               Queue.producer_spec(@org, "webhooks.github", pipeline_id: 1, prefetch_count: 5)

      assert opts[:source_queue] == "org.42.webhooks.github"
      assert opts[:pipeline_id] == 1
    end

    test "refuses an invalid organization or queue name" do
      assert {:error, :organization_required} = Queue.producer_spec(nil, "q", pipeline_id: 1)

      assert {:error, {:invalid_queue, :reserved_prefix}} =
               Queue.producer_spec(@org, "amq.q", pipeline_id: 1)
    end

    test "refuses an adapter that can't report a message's organization" do
      use_recording_adapter(%{})

      assert {:error, :adapter_cannot_attribute_messages} =
               Queue.producer_spec(@org, "q", pipeline_id: 1)
    end
  end

  describe "message_organization_id/2" do
    test "reads the organization the adapter's producer tagged" do
      tagged = %Broadway.Message{data: %{}, metadata: %{organization_id: @org}, acknowledger: nil}
      assert {:ok, @org} = Queue.message_organization_id(Memory, tagged)
    end

    test "is :error for an untagged message or an adapter that can't tell" do
      untagged = %Broadway.Message{data: %{}, acknowledger: nil}
      tagged = %Broadway.Message{data: %{}, metadata: %{organization_id: @org}, acknowledger: nil}

      assert :error = Queue.message_organization_id(Memory, untagged)
      assert :error = Queue.message_organization_id(RecordingDlqQueue, tagged)
      assert :error = Queue.message_organization_id(nil, tagged)
    end
  end

  describe "ack/1" do
    test "delegates to the configured adapter without crashing" do
      message = Message.new(%{event: "test"}, source: "test")
      :ok = Queue.publish(@org, "test_queue", message, [])
      assert :ok = Queue.ack(message)
    end
  end

  describe "reject/2" do
    test "delegates to the configured adapter without crashing" do
      message = Message.new(%{event: "test"}, source: "test")
      :ok = Queue.publish(@org, "test_queue", message, [])
      assert :ok = Queue.reject(message, false)
    end

    test "reject with requeue delegates without crashing" do
      message = Message.new(%{event: "test"}, source: "test", organization_id: @org)
      :ok = Queue.publish(@org, "test_queue", message, [])
      assert :ok = Queue.reject(message, true)
    end
  end

  describe "DLQ facade with an adapter that omits the optional callbacks" do
    # The active adapter in test is Memory, which does not implement the DLQ
    # callbacks. The facade must return a clean upgrade error, not crash.
    test "list_dlq_messages/3 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.list_dlq_messages(@org)
      assert {:error, {:pro_required, :dlq}} = Queue.list_dlq_messages(@org, 10, 5)
    end

    test "dlq_depth/1 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.dlq_depth(@org)
    end

    test "retry_message/2 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.retry_message(@org, 1)
    end

    test "discard_message/2 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.discard_message(@org, 1)
    end

    test "replay_dlq/3 returns pro_required" do
      assert {:error, {:pro_required, :dlq}} = Queue.replay_dlq(@org, %{}, 100)
    end
  end

  describe "DLQ facade scoping" do
    setup :use_recording_adapter

    test "every DLQ call names the organization" do
      Queue.dlq_depth(@org)
      Queue.retry_message(@org, "t1")
      Queue.discard_message(@org, "t2")
      Queue.list_dlq_messages(@org, 10, 20)

      assert_received {:dlq_call, :get_dlq_depth, [@org]}
      assert_received {:dlq_call, :retry_message, [@org, "t1"]}
      assert_received {:dlq_call, :discard_message, [@org, "t2"]}
      assert_received {:dlq_call, :list_dlq_messages, [@org, 10, 20]}
    end

    test "refuses a call without an organization, before reaching the adapter" do
      assert {:error, :organization_required} = Queue.dlq_depth(nil)
      assert {:error, :organization_required} = Queue.list_dlq_messages(nil)
      assert {:error, :organization_required} = Queue.retry_message(nil, "t")
      assert {:error, :organization_required} = Queue.discard_message(nil, "t")
      assert {:error, :organization_required} = Queue.replay_dlq(nil, %{}, 10)

      refute_received {:dlq_call, _, _}
    end

    test "lists only the organization's own dead letters, by logical queue name" do
      Process.put(:recording_dlq_messages, [
        dead_letter("own", "org.42.webhooks.stripe"),
        dead_letter("foreign", "org.43.webhooks.stripe"),
        dead_letter("legacy", "webhooks.stripe"),
        dead_letter("system", "org.42.flux.dlq"),
        dead_letter("unknown", nil)
      ])

      assert {:ok, [only]} = Queue.list_dlq_messages(@org)
      assert only.delivery_tag == "own"
      assert only.original_queue == "webhooks.stripe"
    end

    test "replays by the physical queue of a logical queue filter" do
      assert {:ok, _} = Queue.replay_dlq(@org, %{queue: "webhooks.stripe", source: "s"}, 10)

      assert_received {:dlq_call, :replay_dlq,
                       [@org, %{queue: "org.42.webhooks.stripe", source: "s"}, 10]}
    end

    test "refuses a replay queue filter that reaches outside the organization" do
      assert {:error, {:invalid_queue, :reserved_prefix}} =
               Queue.replay_dlq(@org, %{queue: "org.43.webhooks.stripe"}, 10)

      refute_received {:dlq_call, :replay_dlq, _}
    end
  end

  defp dead_letter(tag, original_queue) do
    %{
      delivery_tag: tag,
      original_queue: original_queue,
      source: "webhook",
      reason: "rejected",
      timestamp: nil,
      payload: %{}
    }
  end
end
