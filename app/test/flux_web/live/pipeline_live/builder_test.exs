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

      # The mandatory Queue Name field carries a required marker.
      assert html =~ ~s(Queue Name<span class="text-error)
    end

    test "pubsub source renders its Pro config form with required markers", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{"label" => "My Source", "sourceConfig" => %{"type" => "pubsub"}}
        })

      # The Pub/Sub type is offered but gated (Community lacks the license).
      assert html =~ "Google Pub/Sub"
      assert html =~ "requires a Pro license"
      # Mandatory fields carry required markers.
      assert html =~ ~s(Project ID<span class="text-error)
      assert html =~ ~s(Subscription<span class="text-error)
    end

    test "rabbitmq_external source renders its Pro config form with required markers", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "rabbitmq_external"}
          }
        })

      # The RabbitMQ (External) type is offered but gated (Community lacks the license).
      assert html =~ "RabbitMQ (External)"
      assert html =~ "requires a Pro license"
      # Mandatory fields carry required markers.
      assert html =~ ~s(Host<span class="text-error)
      assert html =~ ~s(Queue<span class="text-error)
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

  describe "save validation" do
    test "saving the default (valid) pipeline succeeds", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html = render_click(lv, "save")

      assert html =~ "Pipeline saved"
    end

    test "saving a source with a missing mandatory field shows an error toast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      # A webhook source with no webhookPath — the mandatory field is blank.
      ir = %{"nodes" => [%{"type" => "source", "sourceConfig" => %{"type" => "webhook"}}]}
      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})

      html = render_click(lv, "save")

      assert html =~ "Webhook Path"
      refute html =~ "Pipeline saved"
    end

    test "saving with no source node shows an error toast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(%{"nodes" => []})})

      html = render_click(lv, "save")

      assert html =~ "Add and configure a source node"
      refute html =~ "Pipeline saved"
    end
  end
end
