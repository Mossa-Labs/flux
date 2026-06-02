defmodule Flux.Pipeline.Steps.MapTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Steps.Map

  describe "execute/2" do
    test "extracts top-level field and maps to new key" do
      data = %{"name" => "John"}
      config = %{"field" => "name", "to" => "user_name"}

      assert {:ok, %{"name" => "John", "user_name" => "John"}} = Map.execute(data, config)
    end

    test "extracts nested field using dot notation" do
      data = %{"data" => %{"user" => %{"name" => "John"}}}
      config = %{"field" => "data.user.name", "to" => "user_name"}

      assert {:ok, result} = Map.execute(data, config)
      assert result["user_name"] == "John"
      assert result["data"] == %{"user" => %{"name" => "John"}}
    end

    test "extracts deeply nested field (3+ levels)" do
      data = %{"a" => %{"b" => %{"c" => %{"d" => "deep_value"}}}}
      config = %{"field" => "a.b.c.d", "to" => "flat"}

      assert {:ok, result} = Map.execute(data, config)
      assert result["flat"] == "deep_value"
    end

    test "uses default value when field is missing" do
      data = %{"name" => "John"}
      config = %{"field" => "email", "to" => "contact_email", "default" => "unknown"}

      assert {:ok, result} = Map.execute(data, config)
      assert result["contact_email"] == "unknown"
    end

    test "returns nil when field is missing and no default provided" do
      data = %{"name" => "John"}
      config = %{"field" => "email", "to" => "contact_email"}

      assert {:ok, result} = Map.execute(data, config)
      assert result["contact_email"] == nil
    end

    test "uses default when nested path does not exist" do
      data = %{"data" => %{"user" => %{}}}
      config = %{"field" => "data.user.name", "to" => "user_name", "default" => "N/A"}

      assert {:ok, result} = Map.execute(data, config)
      assert result["user_name"] == "N/A"
    end

    test "returns error when 'field' config is missing" do
      data = %{"name" => "John"}
      config = %{"to" => "user_name"}

      assert {:error, "Map step requires 'field' and 'to' in config"} = Map.execute(data, config)
    end

    test "returns error when 'to' config is missing" do
      data = %{"name" => "John"}
      config = %{"field" => "name"}

      assert {:error, "Map step requires 'field' and 'to' in config"} = Map.execute(data, config)
    end

    test "returns error when both 'field' and 'to' are missing" do
      data = %{"name" => "John"}
      config = %{}

      assert {:error, "Map step requires 'field' and 'to' in config"} = Map.execute(data, config)
    end

    test "returns error when data is not a map" do
      assert {:error, "Invalid data or config format"} =
               Map.execute("not_a_map", %{"field" => "x", "to" => "y"})
    end

    test "returns error when config is not a map" do
      assert {:error, "Invalid data or config format"} =
               Map.execute(%{"name" => "John"}, "not_a_map")
    end

    test "returns error when neither data nor config are maps" do
      assert {:error, "Invalid data or config format"} = Map.execute("bad", "bad")
    end

    test "preserves original data alongside mapped field" do
      data = %{"first" => "Jane", "last" => "Doe"}
      config = %{"field" => "first", "to" => "given_name"}

      assert {:ok, result} = Map.execute(data, config)
      assert result["first"] == "Jane"
      assert result["last"] == "Doe"
      assert result["given_name"] == "Jane"
    end
  end
end
