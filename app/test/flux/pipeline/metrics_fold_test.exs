defmodule Flux.Pipeline.MetricsFoldTest do
  @moduledoc "MOS-531: cluster-wide metrics are the fold of each node's local totals."
  use ExUnit.Case, async: true

  alias Flux.Pipeline.Metrics

  test "fold/1 sums per-node metrics into cluster-wide totals" do
    a = %{node: :a@h, events_per_sec: 1.5, processed_total: 10, failed_total: 1}
    b = %{node: :b@h, events_per_sec: 2.0, processed_total: 5, failed_total: 0}

    assert %{events_per_sec: 3.5, processed_total: 15, failed_total: 1} = Metrics.fold([a, b])
  end

  test "fold/1 of a single node returns its own totals" do
    a = %{node: :a@h, events_per_sec: 4.0, processed_total: 7, failed_total: 2}
    assert %{events_per_sec: 4.0, processed_total: 7, failed_total: 2} = Metrics.fold([a])
  end

  test "fold/1 of no nodes is zero" do
    totals = Metrics.fold([])
    assert totals.events_per_sec == 0.0
    assert totals.processed_total == 0
    assert totals.failed_total == 0
  end
end
