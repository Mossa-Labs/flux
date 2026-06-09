defmodule Flux.MeteringTest do
  # async: false — set_active/1 mutates the global registry ETS table.
  use ExUnit.Case, async: false

  alias Flux.Metering

  setup do
    on_exit(fn ->
      Metering.Registry.set_active(Flux.Metering.Providers.Community)
      Application.delete_env(:flux, :test_metering_quota)
      Application.delete_env(:flux, :test_metering_usage)
    end)

    :ok
  end

  describe "metrics/0" do
    test "lists the canonical metric keys" do
      assert Metering.metrics() == [
               :messages_ingested,
               :messages_processed,
               :sink_deliveries,
               :active_pipelines,
               :pipeline_hours
             ]
    end
  end

  describe "Community provider (default)" do
    test "reports zero usage" do
      assert {:ok, usage} = Metering.get_usage(1)
      assert usage.metrics.messages_ingested == 0
      assert usage.metrics.pipeline_hours == 0.0
      assert usage.quota.unlimited
    end

    test "never enforces a quota" do
      assert Metering.check_quota(1) == :ok

      assert Metering.quota_status(1) == %{
               unlimited: true,
               limit: nil,
               usage: 0,
               pct: 0.0,
               state: :ok
             }
    end
  end

  describe "facade delegation" do
    test "routes through the active provider" do
      Metering.Registry.set_active(Flux.MeteringTestProvider)
      Application.put_env(:flux, :test_metering_quota, {:error, {:quota_exceeded, 42}})

      assert Metering.check_quota(1) == {:error, {:quota_exceeded, 42}}
      assert {:ok, %{metrics: %{messages_ingested: 1_234}}} = Metering.get_usage(1)
    end
  end
end
