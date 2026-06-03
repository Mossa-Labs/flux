defmodule FluxWeb.AnomalyLive.IndexTest do
  # async: false — the :live_signals gate swaps the global license provider.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Flux.LicenseHelpers

  describe "community tier (Live Signals not licensed)" do
    setup :register_and_log_in_user

    test "shows the heading and an upgrade prompt instead of signal data", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/intelligence/signals")

      assert html =~ "Live Signals"
      assert html =~ "Live Signals monitoring"
      assert html =~ "View pricing"
      refute html =~ "Active anomalies"
      refute html =~ "No active signals"
    end
  end

  describe "licensed tier (:live_signals entitled)" do
    setup :register_and_log_in_user

    setup do
      state = put_license_tier(:pro)
      on_exit(fn -> reset_license(state) end)
      :ok
    end

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
