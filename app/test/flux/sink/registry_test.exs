defmodule Flux.Sink.RegistryTest do
  use ExUnit.Case, async: false

  alias Flux.Sink.Registry

  describe "Community boot-time registrations" do
    test "http, postgres resolve to their adapters" do
      assert {:ok, Flux.Sink.Adapters.HTTP} = Registry.lookup("http")
      assert {:ok, Flux.Sink.Adapters.Postgres} = Registry.lookup("postgres")
    end

    test "s3 resolves to Stub in Community" do
      assert {:ok, Flux.Sink.Adapters.Stub} = Registry.lookup("s3")
    end

    test "redis resolves to Stub in Community" do
      assert {:ok, Flux.Sink.Adapters.Stub} = Registry.lookup("redis")
    end

    test "mongodb resolves to Stub in Community" do
      assert {:ok, Flux.Sink.Adapters.Stub} = Registry.lookup("mongodb")
    end

    test "slack resolves to Stub in Community" do
      assert {:ok, Flux.Sink.Adapters.Stub} = Registry.lookup("slack")
    end

    test "unknown type returns error" do
      assert {:error, :unknown_type} = Registry.lookup("does-not-exist")
    end

    test "atom types are coerced to strings" do
      assert {:ok, Flux.Sink.Adapters.HTTP} = Registry.lookup(:http)
    end

    test "list/0 returns the registered type keys sorted" do
      types = Registry.list()
      assert "http" in types
      assert "postgres" in types
      assert "s3" in types
      assert types == Enum.sort(types)
    end
  end

  describe "register/2" do
    test "overwrites existing registrations" do
      :ok = Registry.register("s3", Flux.Sink.Adapters.Stub)
      assert {:ok, Flux.Sink.Adapters.Stub} = Registry.lookup("s3")
    end
  end
end
