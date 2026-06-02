defmodule FluxWeb.AnomalyLive.IndexTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "mounts and shows 'Live Signals' heading", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/intelligence/signals")

      assert html =~ "Live Signals"
    end

    test "shows empty state when no pipelines are running", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/intelligence/signals")

      assert html =~ "No active signals"
    end

    test "shows summary cards", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/intelligence/signals")

      assert html =~ "Active anomalies"
      assert html =~ "Highest z-score"
      assert html =~ "Pipelines monitored"
    end
  end

  describe "unauthenticated access" do
    test "redirects to login page", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/intelligence/signals")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
