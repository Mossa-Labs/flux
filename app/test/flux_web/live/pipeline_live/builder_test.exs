defmodule FluxWeb.PipelineLive.BuilderTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "builder page" do
    test "mounts and renders the pipeline-builder container", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines/builder")

      assert html =~ ~s(id="pipeline-builder")
      assert html =~ "Visual Pipeline Builder"
    end

    test "shows Save Pipeline button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines/builder")

      assert html =~ "Save Pipeline"
    end

    test "shows node palette in sidebar", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines/builder")

      assert html =~ "Nodes"
      assert html =~ "Source"
      assert html =~ "Filter"
      assert html =~ "Transform"
    end
  end
end
