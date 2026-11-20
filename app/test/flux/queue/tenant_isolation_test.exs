defmodule Flux.Queue.TenantIsolationTest do
  # Two organizations that pick the same queue name must never see each other's
  # messages, whichever way a message enters the queue: a webhook, another
  # pipeline's destination queue, or the poller.
  use FluxWeb.ConnCase, async: false
  use Oban.Testing, repo: Flux.Repo

  import Flux.PipelinesFixtures

  alias Flux.Accounts
  alias Flux.Pipeline.Runner
  alias Flux.Queue.Registry
  alias Flux.Structure.Organization
  alias Flux.Workers.Poller

  setup do
    Registry.register("loopback", Flux.Test.LoopbackQueue)
    Registry.set_active("loopback")
    on_exit(fn -> Registry.set_active("memory") end)

    attach_processed_telemetry()

    org_a = org()
    org_b = org()

    %{org_a: org_a, org_b: org_b, key_a: api_key(org_a), key_b: api_key(org_b)}
  end

  describe "webhook ingest" do
    test "a pipeline never consumes another organization's webhook", %{
      conn: conn,
      org_a: org_a,
      org_b: org_b,
      key_a: key_a
    } do
      a = run_pipeline(org_a, source_queue: "webhooks.stripe")
      b = run_pipeline(org_b, source_queue: "webhooks.stripe")

      post_webhook(conn, key_a, "stripe", %{"charge" => "ch_1"})

      assert_receive {:processed, ^a}, 2_000
      refute_receive {:processed, ^b}, 300
    end

    test "an organization can't inject into another organization's webhook queue", %{
      conn: conn,
      org_a: org_a,
      org_b: org_b,
      key_b: key_b
    } do
      a = run_pipeline(org_a, source_queue: "webhooks.stripe")
      b = run_pipeline(org_b, source_queue: "webhooks.stripe")

      post_webhook(conn, key_b, "stripe", %{"charge" => "forged"})

      assert_receive {:processed, ^b}, 2_000
      refute_receive {:processed, ^a}, 300
    end
  end

  describe "pipeline destination queue" do
    test "a destination queue stays inside the pipeline's organization", %{
      conn: conn,
      org_a: org_a,
      org_b: org_b,
      key_b: key_b
    } do
      a = run_pipeline(org_a, source_queue: "webhooks.stripe")
      b_control = run_pipeline(org_b, source_queue: "webhooks.stripe")

      _b_forwarder =
        run_pipeline(org_b, source_queue: "webhooks.b-in", destination_queue: "webhooks.stripe")

      post_webhook(conn, key_b, "b-in", %{"charge" => "forged"})

      assert_receive {:processed, ^b_control}, 2_000
      refute_receive {:processed, ^a}, 300
    end
  end

  describe "poller ingest" do
    test "a poll for one organization never reaches another organization's pipeline", %{
      org_a: org_a,
      org_b: org_b
    } do
      a = run_pipeline(org_a, source_queue: "polling.feed")
      b = run_pipeline(org_b, source_queue: "polling.feed")

      assert :ok = perform_job(Poller, %{"source_id" => "feed", "organization_id" => org_b.id})

      assert_receive {:processed, ^b}, 2_000
      refute_receive {:processed, ^a}, 300
    end
  end

  defp run_pipeline(org, attrs) do
    pipeline = pipeline_fixture(org.id, Map.new(attrs))
    start_supervised!({Runner, pipeline}, id: {Runner, pipeline.id})
    pipeline.id
  end

  defp post_webhook(conn, key, source, payload) do
    conn
    |> put_req_header("x-api-key", key)
    |> post(~p"/api/webhooks/#{source}", payload)
    |> json_response(202)
  end

  defp attach_processed_telemetry do
    test_pid = self()
    handler = "tenant-isolation-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:flux, :pipeline, :message, :processed],
      fn _event, _measurements, %{pipeline_id: id}, _ -> send(test_pid, {:processed, id}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp api_key(org) do
    {:ok, raw, _key} = Accounts.create_api_key(org.id, %{name: "ingest", role: "admin"})
    raw
  end

  defp org do
    Flux.Repo.insert!(%Organization{
      name: "Org #{System.unique_integer([:positive])}",
      slug: "org-#{System.unique_integer([:positive])}"
    })
  end
end
