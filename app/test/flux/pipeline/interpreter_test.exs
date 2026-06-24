defmodule Flux.Pipeline.InterpreterTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Interpreter

  describe "execute/2" do
    test "executes empty steps" do
      data = %{"value" => 100}
      config = %{"version" => "1.0", "steps" => []}

      assert {:ok, ^data} = Interpreter.execute(data, config)
    end

    test "executes empty config" do
      data = %{"value" => 100}
      assert {:ok, ^data} = Interpreter.execute(data, %{})
    end

    test "executes rename step" do
      data = %{"old_name" => "test"}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "s1",
            "type" => "native",
            "operation" => "rename",
            "config" => %{"from" => "old_name", "to" => "new_name"}
          }
        ]
      }

      assert {:ok, result} = Interpreter.execute(data, config)
      assert result["new_name"] == "test"
      refute Map.has_key?(result, "old_name")
    end

    test "executes map step" do
      data = %{"nested" => %{"value" => 42}}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "s1",
            "type" => "native",
            "operation" => "map",
            "config" => %{"field" => "nested.value", "to" => "extracted"}
          }
        ]
      }

      assert {:ok, result} = Interpreter.execute(data, config)
      assert result["extracted"] == 42
    end

    test "executes filter step - passes" do
      data = %{"type" => "push"}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "s1",
            "type" => "native",
            "operation" => "filter",
            "config" => %{"field" => "type", "operator" => "eq", "value" => "push"}
          }
        ]
      }

      assert {:ok, ^data} = Interpreter.execute(data, config)
    end

    test "executes filter step - skips" do
      data = %{"type" => "pull"}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "s1",
            "type" => "native",
            "operation" => "filter",
            "config" => %{"field" => "type", "operator" => "eq", "value" => "push"}
          }
        ]
      }

      assert {:skip, :filtered} = Interpreter.execute(data, config)
    end

    test "executes multiple steps in sequence" do
      data = %{"old_field" => "value", "number" => 10}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "s1",
            "type" => "native",
            "operation" => "rename",
            "config" => %{"from" => "old_field", "to" => "new_field"}
          },
          %{
            "id" => "s2",
            "type" => "native",
            "operation" => "filter",
            "config" => %{"field" => "number", "operator" => "gt", "value" => 5}
          }
        ]
      }

      assert {:ok, result} = Interpreter.execute(data, config)
      assert result["new_field"] == "value"
      assert result["number"] == 10
    end

    test "returns error for unknown step type" do
      data = %{"value" => 1}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{"id" => "s1", "type" => "unknown"}
        ]
      }

      assert {:error, "Unknown step type: unknown"} = Interpreter.execute(data, config)
    end

    test "returns error for unknown operation" do
      data = %{"value" => 1}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{"id" => "s1", "type" => "native", "operation" => "unknown", "config" => %{}}
        ]
      }

      assert {:error, "Unknown operation: unknown"} = Interpreter.execute(data, config)
    end

    test "returns error for an invalid pipeline configuration" do
      assert {:error, "Invalid pipeline configuration"} = Interpreter.execute(%{"a" => 1}, "nope")
    end

    test "defaults config to an empty map for a native step without config" do
      data = %{"old" => "v"}

      config = %{
        "version" => "1.0",
        "steps" => [%{"id" => "s1", "type" => "native", "operation" => "rename"}]
      }

      # The missing-config clause dispatches with config => %{}; rename then
      # reports the absent from/to — exercising the default-config branch.
      assert {:error, "Rename step requires 'from' and 'to' in config"} =
               Interpreter.execute(data, config)
    end

    test "executes a lua script step" do
      data = %{"name" => "Jane"}

      config = %{
        "version" => "1.0",
        "steps" => [
          %{
            "id" => "s1",
            "type" => "script",
            "language" => "lua",
            "code" => """
            function transform(data)
              data.processed = true
              return data
            end
            """
          }
        ]
      }

      assert {:ok, result} = Interpreter.execute(data, config)
      assert result["processed"] == true
    end

    test "returns error for a structurally invalid step" do
      config = %{"version" => "1.0", "steps" => [%{"id" => "s1"}]}
      assert {:error, "Invalid step format:" <> _} = Interpreter.execute(%{"a" => 1}, config)
    end
  end
end
