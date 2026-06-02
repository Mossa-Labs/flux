defmodule Flux.AI.ScorerTest do
  use ExUnit.Case, async: true

  alias Flux.AI.Scorer

  describe "z_score/2" do
    test "returns 0 for insufficient data" do
      stats = %{count: 1, sum: 100, sum_sq: 10000}
      assert Scorer.z_score(100, stats) == 0.0
    end

    test "returns 0 for zero variance" do
      stats = %{count: 3, sum: 300, sum_sq: 30000}
      assert Scorer.z_score(100, stats) == 0.0
    end

    test "returns correct z-score for normal distribution" do
      stats = %{
        count: 10,
        sum: 100,
        sum_sq: 1020
      }

      score = Scorer.z_score(10, stats)
      assert score == 0.0

      score = Scorer.z_score(12, stats)
      assert_in_delta score, 1.414, 0.01
    end
  end

  describe "anomaly?/3" do
    test "returns false for normal values" do
      stats = %{count: 10, sum: 100, sum_sq: 1020}
      refute Scorer.anomaly?(10, stats, 2.0)
    end

    test "returns true for anomalous values" do
      stats = %{count: 10, sum: 100, sum_sq: 1020}
      assert Scorer.anomaly?(20, stats, 2.0)
    end
  end

  describe "iqr_score/2" do
    test "returns 0 for values within IQR bounds" do
      values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      assert Scorer.iqr_score(5, values) == 0.0
    end

    test "returns positive score for outliers above upper bound" do
      values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      score = Scorer.iqr_score(20, values)
      assert score > 0
    end

    test "returns positive score for outliers below lower bound" do
      values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      score = Scorer.iqr_score(-10, values)
      assert score > 0
    end

    test "returns 0 for insufficient data" do
      values = [1, 2, 3]
      assert Scorer.iqr_score(100, values) == 0.0
    end
  end
end
