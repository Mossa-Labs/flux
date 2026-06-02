defmodule FluxWeb.SinkLive.IndexTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.SinksFixtures

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "shows empty state when no sinks exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sinks")

      assert html =~ "No sinks configured"
      assert html =~ "Create sinks to send your transformed data"
    end

    test "lists sinks when they exist", %{conn: conn, scope: scope} do
      sink = sink_fixture(scope.organization_id, %{name: "My Webhook Sink"})

      {:ok, _lv, html} = live(conn, ~p"/sinks")

      assert html =~ sink.name
    end

    test "shows sink type badge", %{conn: conn, scope: scope} do
      _sink = sink_fixture(scope.organization_id, %{name: "HTTP Sink", type: "http"})

      {:ok, _lv, html} = live(conn, ~p"/sinks")

      assert html =~ "HTTP"
    end

    test "shows enabled status", %{conn: conn, scope: scope} do
      _sink = sink_fixture(scope.organization_id, %{name: "Active Sink", enabled: true})

      {:ok, _lv, html} = live(conn, ~p"/sinks")

      assert html =~ "Enabled"
    end
  end

  describe "unauthenticated access" do
    test "redirects to login page", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/sinks")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
