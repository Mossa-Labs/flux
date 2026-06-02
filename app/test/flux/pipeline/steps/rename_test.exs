defmodule Flux.Pipeline.Steps.RenameTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Steps.Rename

  describe "execute/2" do
    test "renames an existing field" do
      data = %{"name" => "John", "age" => 30}
      config = %{"from" => "name", "to" => "full_name"}

      assert {:ok, result} = Rename.execute(data, config)
      assert result["full_name"] == "John"
      refute Map.has_key?(result, "name")
      assert result["age"] == 30
    end

    test "returns data unchanged when 'from' field does not exist" do
      data = %{"name" => "John"}
      config = %{"from" => "email", "to" => "contact_email"}

      assert {:ok, ^data} = Rename.execute(data, config)
    end

    test "returns error when 'from' config is missing" do
      data = %{"name" => "John"}
      config = %{"to" => "full_name"}

      assert {:error, "Rename step requires 'from' and 'to' in config"} =
               Rename.execute(data, config)
    end

    test "returns error when 'to' config is missing" do
      data = %{"name" => "John"}
      config = %{"from" => "name"}

      assert {:error, "Rename step requires 'from' and 'to' in config"} =
               Rename.execute(data, config)
    end

    test "returns error when both 'from' and 'to' are missing" do
      data = %{"name" => "John"}
      config = %{}

      assert {:error, "Rename step requires 'from' and 'to' in config"} =
               Rename.execute(data, config)
    end

    test "returns error when data is not a map" do
      assert {:error, "Invalid data or config format"} =
               Rename.execute("not_a_map", %{"from" => "a", "to" => "b"})
    end

    test "returns error when config is not a map" do
      assert {:error, "Invalid data or config format"} =
               Rename.execute(%{"name" => "John"}, "not_a_map")
    end

    test "returns error when neither data nor config are maps" do
      assert {:error, "Invalid data or config format"} = Rename.execute(42, [])
    end

    test "handles renaming to an existing key (overwrites)" do
      data = %{"old_key" => "value1", "new_key" => "value2"}
      config = %{"from" => "old_key", "to" => "new_key"}

      assert {:ok, result} = Rename.execute(data, config)
      assert result["new_key"] == "value1"
      refute Map.has_key?(result, "old_key")
    end

    test "preserves other fields during rename" do
      data = %{"a" => 1, "b" => 2, "c" => 3}
      config = %{"from" => "b", "to" => "beta"}

      assert {:ok, result} = Rename.execute(data, config)
      assert result["a"] == 1
      assert result["beta"] == 2
      assert result["c"] == 3
      refute Map.has_key?(result, "b")
    end
  end
end
