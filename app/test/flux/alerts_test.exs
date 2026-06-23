defmodule Flux.AlertsTest do
  # async: false — set_active/1 mutates the global registry ETS table.
  use ExUnit.Case, async: false

  alias Flux.Alerts

  setup do
    on_exit(fn -> Alerts.Registry.set_active(Flux.Alerts.Providers.Community) end)
    :ok
  end

  describe "catalogs" do
    test "trigger and channel types" do
      assert Alerts.trigger_types() == [
               :anomaly,
               :failure_rate,
               :pipeline_stopped,
               :dlq_depth,
               :freshness_slo,
               :volume_anomaly,
               :schema_drift
             ]

      assert Alerts.channel_types() == [:email, :webhook, :slack]
    end
  end

  describe "Community provider (default)" do
    test "lists nothing and refuses mutations with :pro_required" do
      assert Alerts.list_rules(1) == []
      assert Alerts.list_history(1) == []
      assert Alerts.get_rule(1, 99) == {:error, :not_found}
      assert Alerts.create_rule(1, %{}) == {:error, {:pro_required, :alerting}}
      assert Alerts.delete_rule(1, 1) == {:error, {:pro_required, :alerting}}
      assert Alerts.test_channel(%{"type" => "email"}) == {:error, {:pro_required, :alerting}}
    end
  end

  describe "facade delegation" do
    test "routes through the active provider" do
      Flux.AlertsTestProvider.reset()
      Alerts.Registry.set_active(Flux.AlertsTestProvider)

      assert {:ok, rule} =
               Alerts.create_rule(7, %{
                 "name" => "spike",
                 "trigger_type" => "anomaly",
                 "trigger_config" => %{"threshold" => 3.0},
                 "channels" => [],
                 "cooldown_minutes" => 15
               })

      assert rule.name == "spike"
      assert [%{name: "spike"}] = Alerts.list_rules(7)
      # org-scoped
      assert Alerts.list_rules(8) == []
    end
  end
end
