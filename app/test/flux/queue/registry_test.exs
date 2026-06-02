defmodule Flux.Queue.RegistryTest do
  use ExUnit.Case, async: false

  alias Flux.Queue.Registry

  test "memory resolves to the Memory adapter" do
    assert {:ok, Flux.Queue.Adapters.Memory} = Registry.lookup("memory")
  end

  test "rabbitmq resolves to Stub in Community" do
    assert {:ok, Flux.Queue.Adapters.Stub} = Registry.lookup("rabbitmq")
  end

  test "active/0 returns the configured Community default (memory)" do
    assert {:ok, Flux.Queue.Adapters.Memory} = Registry.active()
  end

  test "list/0 returns registered types without the __active__ pseudo-key" do
    types = Registry.list()
    assert "memory" in types
    assert "rabbitmq" in types
    refute Enum.any?(types, &is_atom/1)
  end

  test "lookup returns error for unknown types" do
    assert {:error, :unknown_type} = Registry.lookup("nats")
  end
end
