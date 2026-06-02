defmodule Flux.Pipeline.StepRegistryTest do
  use ExUnit.Case, async: false

  alias Flux.Pipeline.StepRegistry

  test "native step operations are registered at boot" do
    assert {:ok, Flux.Pipeline.Steps.Map} = StepRegistry.lookup("map")
    assert {:ok, Flux.Pipeline.Steps.Filter} = StepRegistry.lookup("filter")
    assert {:ok, Flux.Pipeline.Steps.Rename} = StepRegistry.lookup("rename")
  end

  test "unknown operations produce a descriptive error" do
    assert {:error, "Unknown operation: " <> _} = StepRegistry.lookup("nonexistent")
  end

  test "Flux.Pipeline.Step.module_for_operation/1 delegates to the registry" do
    assert {:ok, Flux.Pipeline.Steps.Filter} = Flux.Pipeline.Step.module_for_operation("filter")
  end
end
