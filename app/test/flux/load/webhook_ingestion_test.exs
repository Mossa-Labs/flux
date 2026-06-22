defmodule Flux.Load.WebhookIngestionTest do
  @moduledoc """
  Validates the webhook ingestion path (auth + quota + queue publish) accepts a
  high request rate once the per-key burst limit is raised. Excluded by default:

      mix test test/flux/load/webhook_ingestion_test.exs --only load
  """

  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.StructureFixtures

  alias Flux.Load.Benchmarks

  @moduletag :load
  @count 5_000

  setup do
    scope = user_scope_fixture()
    %{org: organization_fixture(scope)}
  end

  @tag :load
  test "accepts requests without burst-limiting", %{org: org} do
    result =
      Benchmarks.run_preset("webhook_ingestion",
        organization_id: org.id,
        count: @count,
        concurrency: 20
      )

    IO.puts(
      "\n[webhook_ingestion] accepted=#{result.extra.accepted}/#{result.sent} " <>
        "thr=#{result.throughput_per_sec} req/s p99=#{Float.round(result.p99_us / 1000, 2)}ms"
    )

    # With the burst limit raised, every request should be accepted (202).
    assert result.failed == 0, "#{result.extra.non_2xx} non-2xx responses (burst limit?)"
    assert result.extra.accepted == result.sent
    assert result.throughput_per_sec > 0

    # ApiAuth casts an async usage write per request; drain that GenServer's
    # mailbox (a sync call) while the sandbox connection is still alive, so no
    # in-flight write races the owner's teardown.
    :sys.get_state(Flux.Accounts.ApiKeyUsage)
  end
end
