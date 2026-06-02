defmodule Flux.AI.Providers.BasicTest do
  use ExUnit.Case, async: true

  alias Flux.AI.Providers.Basic

  test "record/3 is a no-op that returns :ok" do
    assert Basic.record("pipe-1", "metric", 42) == :ok
  end

  test "score/3 returns 0.0 for any input" do
    assert {:ok, +0.0} = Basic.score("pipe-1", %{"metric" => 999}, ["metric"])
  end

  test "list_fields/1 returns an empty list" do
    assert Basic.list_fields("pipe-1") == []
  end

  test "list_anomalous_pipelines/1 returns an empty list" do
    assert Basic.list_anomalous_pipelines(2.0) == []
  end

  test "get_stats/2 returns {:error, :not_found}" do
    assert {:error, :not_found} = Basic.get_stats("pipe-1", "metric")
  end

  test "Flux.AI facade routes through the active provider (Basic in Community)" do
    assert Flux.AI.record("pipe-2", "metric", 100) == :ok
    assert {:ok, +0.0} = Flux.AI.score("pipe-2", %{"metric" => 100}, ["metric"])
    assert Flux.AI.list_fields("pipe-2") == []
  end
end
