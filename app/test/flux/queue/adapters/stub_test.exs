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
end
