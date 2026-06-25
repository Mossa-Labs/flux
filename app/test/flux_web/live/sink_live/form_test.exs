defmodule FluxWeb.SinkLive.FormTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.SinksFixtures

  setup :register_and_log_in_user

  describe "new sink" do
    test "mounts with new action and shows 'New Sink' title", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sinks/new")

      assert html =~ "New Sink"
    end

    test "shows sink type selector", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sinks/new")

      assert html =~ "HTTP"
      assert html =~ "S3"
      assert html =~ "Postgres"
      assert html =~ "BigQuery"
    end

    test "selecting BigQuery shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "bigquery"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Service Account JSON"
    end

    test "selecting Snowflake shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "snowflake"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Account Identifier"
    end

    test "save with valid params creates sink and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      result =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "Test HTTP Sink",
            "config_url" => "https://example.com/webhook",
            "config_method" => "POST"
          }
        })
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/sinks"}}} = result
    end

    test "save with empty name shows validation error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "",
            "config_url" => "https://example.com/webhook"
          }
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can&apos;t be blank" or
               html =~ "can't be blank"
    end
  end

  describe "edit sink" do
    test "mounts with edit action and shows 'Edit Sink' title", %{conn: conn, scope: scope} do
      sink = sink_fixture(scope.organization_id, %{name: "Existing Sink"})

      {:ok, _lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ "Edit Sink"
    end

    test "shows existing sink name in form", %{conn: conn, scope: scope} do
      sink = sink_fixture(scope.organization_id, %{name: "Existing Sink"})

      {:ok, _lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ "Existing Sink"
    end
  end
end
