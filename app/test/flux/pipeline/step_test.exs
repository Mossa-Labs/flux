defmodule Flux.Pipeline.StepTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Step

  describe "module_for_operation/1" do
    test "returns Map module for 'map' operation" do
      assert {:ok, Flux.Pipeline.Steps.Map} = Step.module_for_operation("map")
    end

    test "returns Filter module for 'filter' operation" do
      assert {:ok, Flux.Pipeline.Steps.Filter} = Step.module_for_operation("filter")
    end

    test "returns Rename module for 'rename' operation" do
      assert {:ok, Flux.Pipeline.Steps.Rename} = Step.module_for_operation("rename")
    end

    test "returns error for unknown operation" do
      assert {:error, "Unknown operation: unknown"} = Step.module_for_operation("unknown")
    end

    test "returns error for 'script' (not a registered operation)" do
      assert {:error, "Unknown operation: script"} = Step.module_for_operation("script")
    end

    test "returns error for empty string operation" do
      assert {:error, "Unknown operation: "} = Step.module_for_operation("")
    end
  end
end
