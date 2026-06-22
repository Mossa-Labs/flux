defmodule Flux.Load.SinkDeliveryTest do
  @moduledoc """
  Validates HTTP and Postgres sink delivery throughput end to end. Excluded by
  default:

      mix test test/flux/load/sink_delivery_test.exs --only load

  Requires `async: false` so the runner's async delivery tasks share the sandbox
  connection (and can see the Postgres temp table).
  """

  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  alias Flux.Load.Benchmarks

  @moduletag :load
  @count 2_000

  setup do
    scope = user_scope_fixture()
    %{org: organization_fixture(scope)}
  end

  @tag :load
  test "HTTP sink delivers to the echo target", %{org: org} do
    result = Benchmarks.run_preset("http_sink_delivery", organization_id: org.id, count: @count)

    IO.puts(
      "\n[http_sink] delivered=#{result.extra.sink_delivered} " <>
        "echo_received=#{result.extra.echo_received} thr=#{result.throughput_per_sec}/s"
    )

    assert result.processed >= @count
    assert result.extra.echo_received > 0
    assert result.extra.sink_delivered > 0
  end

  @tag :load
  test "Postgres sink inserts rows", %{org: org} do
    result =
      Benchmarks.run_preset("postgres_sink_delivery", organization_id: org.id, count: @count)

    IO.puts(
      "\n[postgres_sink] delivered=#{result.extra.sink_delivered} " <>
        "rows_inserted=#{result.extra.rows_inserted} thr=#{result.throughput_per_sec}/s"
    )

    assert result.processed >= @count
    assert result.extra.rows_inserted > 0
  end
end
