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

  describe "config panel selection" do
    test "select_node focuses the config panel on the selected node", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/pipelines/builder")

      # Starts with nothing selected.
      assert html =~ "Select a node to configure"

      # Selecting a node (as the React canvas does after adding/clicking one)
      # focuses the config panel on it.
      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{"label" => "My Source", "sourceConfig" => %{"type" => "queue"}}
        })

      assert html =~ "Source Node"
      assert html =~ "My Source"
      refute html =~ "Select a node to configure"
    end

    test "empty select_node clears the config panel back to the empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      render_hook(lv, "select_node", %{
        "nodeId" => "node_1",
        "nodeType" => "source",
        "nodeData" => %{"label" => "My Source"}
      })

      html = render_hook(lv, "select_node", %{})

      assert html =~ "Select a node to configure"
      refute html =~ "My Source"
    end
  end
end
