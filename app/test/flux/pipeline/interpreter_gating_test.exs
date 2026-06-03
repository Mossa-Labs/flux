defmodule Flux.Pipeline.InterpreterGatingTest do
  # async: false — swaps the global license provider.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  alias Flux.Pipeline.Interpreter

  @ai_step %{
    "version" => "1.0",
    "steps" => [
      %{
        "id" => "s1",
        "type" => "ai",
        "operation" => "anomaly_detect",
        "config" => %{"fields" => ["amount"], "threshold" => 2.0}
      }
    ]
  }

  test "AI anomaly step is skipped (data unchanged) on the community tier" do
    data = %{"amount" => 9_999_999}

    # Community tier is not entitled to :advanced_ai — the step passes through.
    assert {:ok, ^data} = Interpreter.execute(data, @ai_step)
    refute Map.has_key?(data, "_anomaly")
  end

  test "AI anomaly step runs when :advanced_ai is licensed" do
    data = %{"amount" => 100}

    with_license_tier(:pro, fn ->
      # The active AI provider (Basic) scores 0.0, so no anomaly is flagged,
      # but the step executes the scoring path rather than being skipped.
      assert {:ok, result} = Interpreter.execute(data, @ai_step)
      assert result == data
    end)
  end
end
