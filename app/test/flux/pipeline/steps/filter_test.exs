defmodule Flux.Pipeline.Steps.FilterTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Steps.Filter

  describe "execute/2" do
    test "eq operator - matches" do
      data = %{"status" => "active"}
      config = %{"field" => "status", "operator" => "eq", "value" => "active"}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "eq operator - doesn't match" do
      data = %{"status" => "inactive"}
      config = %{"field" => "status", "operator" => "eq", "value" => "active"}

      assert {:skip, :filtered} = Filter.execute(data, config)
    end

    test "ne operator - matches" do
      data = %{"status" => "inactive"}
      config = %{"field" => "status", "operator" => "ne", "value" => "active"}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "in operator - matches" do
      data = %{"type" => "push"}
      config = %{"field" => "type", "operator" => "in", "values" => ["push", "pull"]}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "in operator - doesn't match" do
      data = %{"type" => "delete"}
      config = %{"field" => "type", "operator" => "in", "values" => ["push", "pull"]}

      assert {:skip, :filtered} = Filter.execute(data, config)
    end

    test "not_in operator - matches" do
      data = %{"type" => "delete"}
      config = %{"field" => "type", "operator" => "not_in", "values" => ["push", "pull"]}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "gt operator - matches" do
      data = %{"count" => 10}
      config = %{"field" => "count", "operator" => "gt", "value" => 5}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "gt operator - doesn't match" do
      data = %{"count" => 3}
      config = %{"field" => "count", "operator" => "gt", "value" => 5}

      assert {:skip, :filtered} = Filter.execute(data, config)
    end

    test "gte operator" do
      data = %{"count" => 5}
      config = %{"field" => "count", "operator" => "gte", "value" => 5}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "lt operator" do
      data = %{"count" => 3}
      config = %{"field" => "count", "operator" => "lt", "value" => 5}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "lte operator" do
      data = %{"count" => 5}
      config = %{"field" => "count", "operator" => "lte", "value" => 5}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "contains operator" do
      data = %{"message" => "hello world"}
      config = %{"field" => "message", "operator" => "contains", "value" => "world"}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "matches operator (regex)" do
      data = %{"email" => "test@example.com"}
      config = %{"field" => "email", "operator" => "matches", "value" => "^[^@]+@[^@]+$"}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "nested field access" do
      data = %{"user" => %{"status" => "active"}}
      config = %{"field" => "user.status", "operator" => "eq", "value" => "active"}

      assert {:ok, ^data} = Filter.execute(data, config)
    end

    test "returns error when field is missing from config" do
      data = %{"value" => 1}
      config = %{"operator" => "eq", "value" => 1}

      assert {:error, _} = Filter.execute(data, config)
    end

    test "returns error when operator is missing from config" do
      data = %{"value" => 1}
      config = %{"field" => "value", "value" => 1}

      assert {:error, _} = Filter.execute(data, config)
    end
  end
end
