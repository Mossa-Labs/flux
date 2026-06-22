defmodule Flux.Load.Stats do
  @moduledoc """
  Latency statistics over a list of samples (microseconds).

  Percentiles use the nearest-rank method: sort once, then for percentile `p`
  pick the value at index `ceil(p/100 * n) - 1`. This is exact (no
  interpolation), allocation-light, and standard for latency p99 reporting.
  No external dependency.
  """

  @empty %{count: 0, min: 0, max: 0, mean: 0.0, p50: 0, p95: 0, p99: 0}

  @doc """
  Returns `%{count, min, max, mean, p50, p95, p99}` for a list of numbers.

  An empty list yields all-zero stats.
  """
  def summary([]), do: @empty

  def summary(values) when is_list(values) do
    sorted = Enum.sort(values)
    n = length(sorted)

    %{
      count: n,
      min: hd(sorted),
      max: List.last(sorted),
      mean: Enum.sum(sorted) / n,
      p50: at_percentile(sorted, 50, n),
      p95: at_percentile(sorted, 95, n),
      p99: at_percentile(sorted, 99, n)
    }
  end

  @doc """
  Returns a map of `percentile => value` for the requested percentiles.
  """
  def percentiles(values, ps) when is_list(values) and is_list(ps) do
    sorted = Enum.sort(values)
    n = length(sorted)
    Map.new(ps, fn p -> {p, at_percentile(sorted, p, n)} end)
  end

  defp at_percentile(_sorted, _p, 0), do: 0

  defp at_percentile(sorted, p, n) do
    idx = max(0, ceil(p / 100 * n) - 1)
    Enum.at(sorted, idx)
  end
end
