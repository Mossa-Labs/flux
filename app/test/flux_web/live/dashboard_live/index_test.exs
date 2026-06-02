defmodule FluxWeb.DashboardLive.IndexTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "mounts and shows Dashboard heading", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Dashboard"
    end

    test "shows stat cards with zero values when no pipelines exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Active Pipelines"
      assert html =~ "Events / Sec"
      assert html =~ "Anomalies"
      assert html =~ "Failed Messages"
    end

    test "shows System Health section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "System Health"
    end
  end

  describe "unauthenticated access" do
    test "redirects to login page", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/dashboard")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
