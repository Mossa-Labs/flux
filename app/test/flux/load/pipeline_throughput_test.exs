defmodule Flux.Load.PipelineThroughputTest do
  @moduledoc """
  Throughput regression guard for a single pipeline at max rate. The headline
  "1,000,000+ messages/minute" claim is validated under fan-out in
  `Flux.Load.ConcurrencyTest`; this asserts a conservative single-pipeline floor
  so gross regressions are caught. Excluded by default:

      mix test test/flux/load/pipeline_throughput_test.exs --only load
  """

  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  alias Flux.Load.{Benchmarks, Scenario}

  @moduletag :load
  @count 50_000
  # Conservative floor — real numbers are much higher; this only catches regressions.
  @floor_per_sec 5_000

  setup do
    scope = user_scope_fixture()
    %{org: organization_fixture(scope)}
  end

  @tag :load
  test "single pipeline sustains throughput and loses no messages", %{org: org} do
    result =
      Scenario.run(
        name: "throughput",
        organization_id: org.id,
        steps: [Benchmarks.step_ir("map")],
        rate: 0,
        count: @count
      )

    IO.puts(
      "\n[throughput] sent=#{result.sent} processed=#{result.processed} " <>
        "thr=#{result.throughput_per_sec}/s (#{Float.round(result.throughput_per_sec * 60 / 1_000_000, 2)}M/min)"
    )

    handled = result.processed + result.skipped + result.failed
    assert handled >= @count, "expected all #{@count} messages handled, got #{handled}"
    assert result.failed == 0
    assert result.throughput_per_sec > @floor_per_sec
  end
end
