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

  test "configure/3 and record_observation/2 are no-ops returning :ok (advanced detection is Pro)" do
    assert Basic.configure("pipe-1", :seasonal, %{"period" => 7}) == :ok
    assert Basic.record_observation("pipe-1", %{"country" => "US", "amount" => 5}) == :ok
  end

  test "Flux.AI facade routes through the active provider (Basic in Community)" do
    assert Flux.AI.record("pipe-2", "metric", 100) == :ok
    assert {:ok, +0.0} = Flux.AI.score("pipe-2", %{"metric" => 100}, ["metric"])
    assert Flux.AI.list_fields("pipe-2") == []
  end

  test "facade configure/record_observation are safe in Community (no crash)" do
    assert Flux.AI.configure("pipe-3", :multivariate, %{"fields" => ["a", "b"]}) == :ok
    assert Flux.AI.record_observation("pipe-3", %{"a" => 1, "b" => 2}) == :ok
  end
end
