defmodule Flux.Source.RegistryTest do
  use ExUnit.Case, async: false

  alias Flux.Source.Registry

  describe "Community boot-time registrations" do
    test "webhook, poll resolve to their adapters" do
      assert {:ok, Flux.Source.Adapters.Webhook} = Registry.lookup("webhook")
      assert {:ok, Flux.Source.Adapters.Poll} = Registry.lookup("poll")
    end

    test "kafka resolves to Stub in Community (real Kafka is Pro)" do
      assert {:ok, Flux.Source.Adapters.Stub} = Registry.lookup("kafka")
    end

    test "unknown type returns error" do
      assert {:error, :unknown_type} = Registry.lookup("does-not-exist")
    end

    test "atom types are coerced to strings" do
      assert {:ok, Flux.Source.Adapters.Webhook} = Registry.lookup(:webhook)
    end

    test "list/0 returns the registered type keys sorted" do
      types = Registry.list()
      assert "webhook" in types
      assert "poll" in types
      assert "kafka" in types
      assert types == Enum.sort(types)
    end
  end
end
