defmodule Flux.ObservabilityTest do
  # async: false — set_active/1 mutates the global registry ETS table.
  use ExUnit.Case, async: false

  alias Flux.Observability

  setup do
    on_exit(fn -> Observability.Registry.set_active(Flux.Observability.Providers.Community) end)
    :ok
  end

  describe "Community provider (default)" do
    test "lists nothing and refuses mutations with :pro_required" do
      assert Observability.list_source_health(1) == []
      assert Observability.list_recent_drift(1, "github") == []
      assert Observability.get_slo(1, "github") == {:error, :not_found}

      assert Observability.upsert_slo(1, "github", %{}) ==
               {:error, {:pro_required, :observability}}

      assert Observability.delete_slo(1, "github") == {:error, {:pro_required, :observability}}
    end
  end

  describe "facade delegation" do
    test "routes through the active provider" do
      Flux.ObservabilityTestProvider.reset()
      Observability.Registry.set_active(Flux.ObservabilityTestProvider)

      assert {:ok, slo} =
               Observability.upsert_slo(7, "github", %{
                 "expected_interval_seconds" => 900,
                 "warn_after_seconds" => 60
               })

      assert slo.expected_interval_seconds == 900
      assert {:ok, ^slo} = Observability.get_slo(7, "github")
      # org-scoped
      assert Observability.get_slo(8, "github") == {:error, :not_found}
    end
  end
end
