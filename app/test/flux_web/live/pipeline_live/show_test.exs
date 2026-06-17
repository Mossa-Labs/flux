defmodule FluxWeb.PipelineLive.ShowTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.PipelinesFixtures

  alias Flux.Pipelines

  setup :register_and_log_in_user

  # Pipeline with two versions: v1 (empty) and v2 (a filter step).
  defp versioned_pipeline(org_id) do
    pipeline = pipeline_fixture(org_id)

    {:ok, pipeline} =
      Pipelines.update_pipeline(pipeline, %{
        steps: %{
          "version" => "1.0",
          "steps" => [%{"type" => "native", "operation" => "filter", "config" => %{}}]
        }
      })

    pipeline
  end

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

  describe "version history" do
    test "History tab lists versions with summaries", %{conn: conn, scope: scope} do
      pipeline = versioned_pipeline(scope.organization_id)

      {:ok, lv, _html} = live(conn, ~p"/pipelines/#{pipeline.id}")

      html = render_click(lv, "switch_tab", %{"tab" => "history"})

      assert html =~ "Version History"
      assert html =~ "Added filter step"
      assert html =~ "Created pipeline"
      assert html =~ "Current"
    end

    test "diff toggles open for a version", %{conn: conn, scope: scope} do
      pipeline = versioned_pipeline(scope.organization_id)

      {:ok, lv, _html} = live(conn, ~p"/pipelines/#{pipeline.id}")
      render_click(lv, "switch_tab", %{"tab" => "history"})
      html = render_click(lv, "toggle_diff", %{"version" => "1"})

      assert html =~ "source_queue"
    end

    test "rollback creates a new version and flashes", %{conn: conn, scope: scope} do
      pipeline = versioned_pipeline(scope.organization_id)

      {:ok, lv, _html} = live(conn, ~p"/pipelines/#{pipeline.id}")
      render_click(lv, "switch_tab", %{"tab" => "history"})
      html = render_click(lv, "rollback", %{"version" => "1"})

      assert html =~ "Rolled back to version 1"
      assert Enum.map(Pipelines.list_pipeline_versions(pipeline.id), & &1.version) == [3, 2, 1]
    end

    test "shows stale-version banner when running config lags latest", %{conn: conn, scope: scope} do
      pipeline = versioned_pipeline(scope.organization_id)
      {:ok, _} = Pipelines.set_running_version(pipeline, 1)

      {:ok, _lv, html} = live(conn, ~p"/pipelines/#{pipeline.id}")

      assert html =~ "stale-version-banner"
      assert html =~ "restart the pipeline"
    end
  end
end
