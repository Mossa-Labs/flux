defmodule Flux.Queue.MessageTest do
  use ExUnit.Case, async: true

  alias Flux.Queue.Message

  describe "new/2" do
    test "creates a message with required fields" do
      message = Message.new(%{event: "test"})

      assert is_binary(message.id)
      assert message.payload == %{event: "test"}
      assert message.source == "unknown"
      assert %DateTime{} = message.inserted_at
      assert message.metadata == %{}
      assert message.adapter_meta == %{}
    end

    test "accepts source option" do
      message = Message.new(%{data: 1}, source: "webhook")

      assert message.source == "webhook"
    end

    test "accepts correlation_id option" do
      message = Message.new(%{data: 1}, correlation_id: "req-123")

      assert message.correlation_id == "req-123"
    end

    test "accepts metadata option" do
      metadata = %{user_agent: "test", ip: "127.0.0.1"}
      message = Message.new(%{data: 1}, metadata: metadata)

      assert message.metadata == metadata
    end

    test "generates unique IDs" do
      messages = for _ <- 1..100, do: Message.new(%{})
      ids = Enum.map(messages, & &1.id)

      assert Enum.uniq(ids) == ids
    end
  end
end
