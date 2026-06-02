defmodule Flux.AI.Scorer do
  @moduledoc """
  Statistical scoring functions for anomaly detection using Nx.

  Provides z-score calculation and other statistical measures for
  detecting anomalous values in data streams.
  """

  import Nx.Defn

  @doc """
  Calculates the z-score for a value given statistics.

  Z-score = (value - mean) / std_dev

  Returns 0.0 if there's insufficient data or zero variance.
  """
  def z_score(value, stats) when is_map(stats) do
    count = Map.get(stats, :count, 0)

    if count < 2 do
      0.0
    else
      sum = Map.get(stats, :sum, 0)
      sum_sq = Map.get(stats, :sum_sq, 0)

      mean = sum / count
      variance = sum_sq / count - mean * mean

      if variance <= 0 do
        0.0
      else
        std_dev = :math.sqrt(variance)
        abs(value - mean) / std_dev
      end
    end
  end

  @doc """
  Batch z-score calculation using Nx tensors.

  Takes a tensor of values and returns a tensor of z-scores.
  """
  defn z_scores_batch(values) do
    mean = Nx.mean(values)
    std_dev = Nx.standard_deviation(values)

    safe_std =
      Nx.select(
        Nx.greater(std_dev, 0),
        std_dev,
        Nx.tensor(1.0)
      )

    Nx.abs(values - mean) / safe_std
  end

  @doc """
  Checks if a value is an anomaly based on z-score threshold.
  """
  def anomaly?(value, stats, threshold \\ 2.0) do
    z_score(value, stats) > threshold
  end

  @doc """
  Calculates the Interquartile Range (IQR) score for outlier detection.

  Values below Q1 - 1.5*IQR or above Q3 + 1.5*IQR are considered outliers.
  Returns a score indicating how far outside the IQR bounds the value is.
  """
  def iqr_score(value, values) when is_list(values) and length(values) >= 4 do
    sorted = Enum.sort(values)
    n = length(sorted)

    q1_idx = div(n, 4)
    q3_idx = div(3 * n, 4)

    q1 = Enum.at(sorted, q1_idx)
    q3 = Enum.at(sorted, q3_idx)

    iqr = q3 - q1

    if iqr == 0 do
      0.0
    else
      lower_bound = q1 - 1.5 * iqr
      upper_bound = q3 + 1.5 * iqr

      cond do
        value < lower_bound -> (lower_bound - value) / iqr
        value > upper_bound -> (value - upper_bound) / iqr
        true -> 0.0
      end
    end
  end

  def iqr_score(_value, _values), do: 0.0
end
