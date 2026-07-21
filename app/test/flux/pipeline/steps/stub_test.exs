defmodule Flux.Pipeline.Steps.StubTest do
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Steps.Stub

  test "passes data through unchanged (fail-open)" do
    data = %{"note" => "email jane@example.com", "n" => 1}
    assert {:ok, ^data} = Stub.execute(data, %{})
  end

  test "ignores config and never errors on odd input" do
    assert {:ok, %{}} = Stub.execute(%{}, %{"mask" => "hash"})
    assert {:ok, "not a map"} = Stub.execute("not a map", %{})
  end

  test "redact/classify operations resolve to the stub on a Community build" do
    assert {:ok, Flux.Pipeline.Steps.Stub} = Flux.Pipeline.StepRegistry.lookup("redact")
    assert {:ok, Flux.Pipeline.Steps.Stub} = Flux.Pipeline.StepRegistry.lookup("classify")
  end
end
