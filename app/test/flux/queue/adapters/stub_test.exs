defmodule Flux.Queue.Adapters.StubTest do
  use ExUnit.Case, async: false

  alias Flux.Queue.Adapters.Stub
  alias Flux.Queue.Message

  setup do
    start_supervised!({Stub, name: :test_stub_queue})
    :ok
  end

  test "publish/3 returns pro_required" do
    msg = Message.new(%{event: "test"}, source: "api")
    assert {:error, {:pro_required, :pro_queue}} = Stub.publish("q", msg, [])
  end

  test "ack/1 returns pro_required" do
    msg = Message.new(%{event: "test"}, source: "api")
    assert {:error, {:pro_required, :pro_queue}} = Stub.ack(msg)
  end

  test "reject/2 returns pro_required" do
    msg = Message.new(%{event: "test"}, source: "api")
    assert {:error, {:pro_required, :pro_queue}} = Stub.reject(msg, false)
  end

  test "producer_spec/1 raises with a clear upgrade message" do
    assert_raise RuntimeError, ~r/Flux Pro/, fn -> Stub.producer_spec(queue: "q") end
  end

  test "list_dlq_messages/2 returns pro_required for :dlq" do
    assert {:error, {:pro_required, :dlq}} = Stub.list_dlq_messages(50, 0)
  end

  test "get_dlq_depth/0 returns pro_required for :dlq" do
    assert {:error, {:pro_required, :dlq}} = Stub.get_dlq_depth()
  end

  test "retry_message/1 returns pro_required for :dlq" do
    assert {:error, {:pro_required, :dlq}} = Stub.retry_message(1)
  end

  test "discard_message/1 returns pro_required for :dlq" do
    assert {:error, {:pro_required, :dlq}} = Stub.discard_message(1)
  end
end
