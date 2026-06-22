defmodule Flux.Load.PipelineLatencyTest do
  @moduledoc """
  Validates the "<5ms p99 message processing latency" claim across the native
  step path and a simple Lua transform. Excluded by default; run with:

      mix test test/flux/load/pipeline_latency_test.exs --only load
  """

  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  alias Flux.Load.Benchmarks

  @moduletag :load
  # Modest count keeps the test quick while still producing a stable p99.
  @count 20_000

  setup do
    scope = user_scope_fixture()
    %{org: organization_fixture(scope)}
  end

  @tag :load
  test "passthrough p99 < 5ms", %{org: org} do
    assert_p99_under_5ms("passthrough_latency", org)
  end

  @tag :load
  test "all native steps p99 < 5ms", %{org: org} do
    assert_p99_under_5ms("native_steps_latency", org)
  end

  @tag :load
  test "lua script p99 < 5ms", %{org: org} do
    assert_p99_under_5ms("script_lua_latency", org)
  end

  defp assert_p99_under_5ms(preset, org) do
    result = Benchmarks.run_preset(preset, organization_id: org.id, count: @count)

    IO.puts(
      "\n[#{preset}] processed=#{result.processed} " <>
        "p50=#{us(result.p50_us)} p95=#{us(result.p95_us)} p99=#{us(result.p99_us)} " <>
        "thr=#{result.throughput_per_sec}/s"
    )

    assert result.processed > 0, "expected messages to be processed"
    assert result.failed == 0, "expected no failed messages, got #{result.failed}"

    assert result.p99_us < 5_000,
           "p99 #{us(result.p99_us)} exceeds the <5ms claim — validate or correct the claim"
  end

  defp us(v), do: "#{Float.round(v / 1000, 3)}ms"
end
