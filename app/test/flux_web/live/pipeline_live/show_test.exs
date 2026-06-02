defmodule FluxWeb.PipelineLive.ShowTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.PipelinesFixtures

  setup :register_and_log_in_user

  describe "pipeline details" do
    test "shows pipeline name and status", %{conn: conn, scope: scope} do
      pipeline =
        pipeline_fixture(scope.organization_id, %{
          name: "Data Enrichment",
          status: "stopped",
          source_queue: "events.raw"
        })

      {:ok, _lv, html} = live(conn, ~p"/pipelines/#{pipeline.id}")

      assert html =~ "Data Enrichment"
      assert html =~ "Stopped"
      assert html =~ "events.raw"
    end

    test "shows source queue in configuration section", %{conn: conn, scope: scope} do
      pipeline =
        pipeline_fixture(scope.organization_id, %{
          source_queue: "ingest.webhooks"
        })

      {:ok, _lv, html} = live(conn, ~p"/pipelines/#{pipeline.id}")

      assert html =~ "Source Queue"
      assert html =~ "ingest.webhooks"
    end

    test "shows 'No sinks configured' when sink_ids is empty", %{conn: conn, scope: scope} do
      pipeline = pipeline_fixture(scope.organization_id, %{sink_ids: []})

      {:ok, _lv, html} = live(conn, ~p"/pipelines/#{pipeline.id}")

      assert html =~ "No sinks configured"
    end

    test "redirects with flash when pipeline does not exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/pipelines", flash: flash}}} =
               live(conn, ~p"/pipelines/999999999")

      assert flash["error"] == "Pipeline not found"
    end
  end
end
