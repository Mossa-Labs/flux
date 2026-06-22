defmodule Flux.Load.StatsTest do
  # Pure unit test (no :load tag) — runs by default so percentile math is covered
  # in CI without needing the heavy load suite.
  use ExUnit.Case, async: true

  alias Flux.Load.Stats

  describe "summary/1" do
    test "empty list yields zeros" do
      assert Stats.summary([]) == %{count: 0, min: 0, max: 0, mean: 0.0, p50: 0, p95: 0, p99: 0}
    end

    test "computes count, min, max and mean" do
      s = Stats.summary([10, 20, 30, 40])
      assert s.count == 4
      assert s.min == 10
      assert s.max == 40
      assert s.mean == 25.0
    end

    test "nearest-rank percentiles on 1..100" do
      s = Stats.summary(Enum.shuffle(1..100))
      # ceil(p/100 * 100) - 1 -> index p-1 -> value p
      assert s.p50 == 50
      assert s.p95 == 95
      assert s.p99 == 99
    end

    test "p99 reflects the tail" do
      # 98 fast samples + 2 slow ones (the top 1% of 100); nearest-rank p99
      # (index ceil(0.99*100)-1 = 98) must surface the slow tail.
      s = Stats.summary([100_000, 100_000 | List.duplicate(1, 98)])
      assert s.p99 == 100_000
      assert s.p50 == 1
    end
  end

  describe "percentiles/2" do
    test "returns a map keyed by requested percentile" do
      assert Stats.percentiles(1..100 |> Enum.to_list(), [50, 90]) == %{50 => 50, 90 => 90}
    end
  end
end
