defmodule Flux.Pipeline.Steps.ScriptTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Steps.Script

  describe "execute/2" do
    test "simple Lua script adds a field" do
      data = %{"name" => "John"}

      config = %{
        "code" => """
        function transform(data)
          data.processed = true
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["name"] == "John"
      assert result["processed"] == true
    end

    test "Lua script modifies an existing field" do
      data = %{"count" => 5.0}

      config = %{
        "code" => """
        function transform(data)
          data.count = data.count * 2
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["count"] == 10.0
    end

    test "Lua script concatenates strings" do
      data = %{"first" => "Jane", "last" => "Doe"}

      config = %{
        "code" => """
        function transform(data)
          data.full_name = data.first .. " " .. data.last
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["full_name"] == "Jane Doe"
    end

    test "returns error when code config is missing" do
      data = %{"name" => "John"}
      config = %{}

      assert {:error, "Script step requires 'code' in config"} = Script.execute(data, config)
    end

    test "returns error when code config is empty string" do
      data = %{"name" => "John"}
      config = %{"code" => ""}

      assert {:error, "Script step requires 'code' in config"} = Script.execute(data, config)
    end

    test "returns error when data is not a map" do
      config = %{"code" => "function transform(data) return data end"}

      assert {:error, "Invalid data or config format"} = Script.execute("not_a_map", config)
    end

    test "returns error when config is not a map" do
      assert {:error, "Invalid data or config format"} =
               Script.execute(%{"name" => "John"}, "not_a_map")
    end

    test "times out on infinite loop" do
      data = %{"name" => "John"}

      config = %{
        "code" => """
        function transform(data)
          while true do end
          return data
        end
        """,
        "timeout_ms" => 100
      }

      assert {:error, "Script execution timed out after 100ms"} = Script.execute(data, config)
    end

    test "sandbox restricts io global" do
      data = %{}

      config = %{
        "code" => """
        function transform(data)
          data.has_io = (io ~= nil)
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["has_io"] == false
    end

    test "sandbox restricts file global" do
      data = %{}

      config = %{
        "code" => """
        function transform(data)
          data.has_file = (file ~= nil)
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["has_file"] == false
    end

    test "sandbox restricts require global" do
      data = %{}

      config = %{
        "code" => """
        function transform(data)
          data.has_require = (require ~= nil)
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["has_require"] == false
    end

    test "sandbox restricts loadfile global" do
      data = %{}

      config = %{
        "code" => """
        function transform(data)
          data.has_loadfile = (loadfile ~= nil)
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["has_loadfile"] == false
    end

    test "sandbox restricts package global" do
      data = %{}

      config = %{
        "code" => """
        function transform(data)
          data.has_package = (package ~= nil)
          return data
        end
        """
      }

      assert {:ok, result} = Script.execute(data, config)
      assert result["has_package"] == false
    end

    test "returns error on Lua syntax error" do
      data = %{"name" => "John"}

      config = %{
        "code" => """
        function transform(data
          return data
        end
        """
      }

      assert {:error, _reason} = Script.execute(data, config)
    end

    test "returns error on Lua runtime error" do
      data = %{"name" => "John"}

      config = %{
        "code" => """
        function transform(data)
          error("something went wrong")
          return data
        end
        """
      }

      assert {:error, _reason} = Script.execute(data, config)
    end
  end
end
