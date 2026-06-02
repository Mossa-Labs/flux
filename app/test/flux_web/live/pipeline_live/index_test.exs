defmodule FluxWeb.PipelineLive.IndexTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.PipelinesFixtures

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "shows empty state when no pipelines exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines")

      assert html =~ "No pipelines yet"
      assert html =~ "Create your first pipeline"
    end

    test "lists pipelines when they exist", %{conn: conn, scope: scope} do
      pipeline = pipeline_fixture(scope.organization_id, %{name: "My ETL Pipeline"})

      {:ok, _lv, html} = live(conn, ~p"/pipelines")

      assert html =~ pipeline.name
      assert html =~ pipeline.source_queue
    end

    test "shows pipeline status badge", %{conn: conn, scope: scope} do
      _pipeline =
        pipeline_fixture(scope.organization_id, %{name: "Stopped Pipeline", status: "stopped"})

      {:ok, _lv, html} = live(conn, ~p"/pipelines")

      assert html =~ "Stopped"
    end

    test "delete event removes pipeline", %{conn: conn, scope: scope} do
      pipeline = pipeline_fixture(scope.organization_id, %{name: "Pipeline To Delete"})

      {:ok, lv, html} = live(conn, ~p"/pipelines")
      assert html =~ "Pipeline To Delete"

      lv
      |> element(~s(button[phx-click="delete"][phx-value-id="#{pipeline.id}"]))
      |> render_click()

      refute render(lv) =~ "Pipeline To Delete"
    end
  end

  describe "unauthenticated access" do
    test "redirects to login page", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/pipelines")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
