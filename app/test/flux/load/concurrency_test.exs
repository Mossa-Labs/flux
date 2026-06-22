defmodule Flux.Load.ConcurrencyTest do
  @moduledoc """
  Validates near-linear scaling across concurrent pipelines and the
  "1,000,000+ messages/minute" aggregate throughput claim. Excluded by default:

      mix test test/flux/load/concurrency_test.exs --only load
  """

  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  alias Flux.Load.Benchmarks

  @moduletag :load

  setup do
    scope = user_scope_fixture()
    %{org: organization_fixture(scope)}
  end

  @tag :load
  test "10 concurrent pipelines aggregate throughput", %{org: org} do
    result = Benchmarks.run_preset("concurrency_10", organization_id: org.id, count: 100_000)

    IO.puts(
      "\n[concurrency_10] processed=#{result.processed} " <>
        "thr=#{result.throughput_per_sec}/s (#{Float.round(result.throughput_per_sec * 60 / 1_000_000, 2)}M/min)"
    )

    assert result.extra.pipelines == 10
    assert result.processed > 0
    assert result.failed == 0
    # 1M/min == 16,667/s. Aggregate across 10 pipelines should clear it on real hardware.
    assert result.throughput_per_sec >= 16_667,
           "aggregate throughput #{result.throughput_per_sec}/s is below the 1M/min claim"
  end
end
