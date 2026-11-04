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

  describe "a sink whose stored secret can't be decrypted (MOS-665)" do
    setup :register_and_log_in_user

    @tag :capture_log
    test "the list still renders and flags only that sink", %{conn: conn, scope: scope} do
      good = sink_fixture(scope.organization_id, %{name: "Healthy Sink"})
      bad = undecryptable_sink_fixture(scope.organization_id, %{name: "Broken Sink"})

      {:ok, lv, html} = live(conn, ~p"/sinks")

      assert html =~ "Healthy Sink"
      assert html =~ "Broken Sink"
      assert has_element?(lv, "#sink-#{bad.id}-undecryptable", "Credentials need re-entering")
      assert has_element?(lv, ~s|#sink-#{bad.id}-undecryptable[href="/sinks/#{bad.id}/edit"]|)
      refute has_element?(lv, "#sink-#{good.id}-undecryptable")
    end

    @tag :capture_log
    test "testing the connection explains what to do", %{conn: conn, scope: scope} do
      bad = undecryptable_sink_fixture(scope.organization_id)

      {:ok, lv, _html} = live(conn, ~p"/sinks")

      html =
        lv |> element(~s|button[phx-click="test"][phx-value-id="#{bad.id}"]|) |> render_click()

      assert html =~ "Stored credentials can&#39;t be decrypted"
    end

    @tag :capture_log
    test "the broken sink can still be disabled", %{conn: conn, scope: scope} do
      bad = undecryptable_sink_fixture(scope.organization_id)

      {:ok, lv, _html} = live(conn, ~p"/sinks")

      html =
        lv |> element(~s|button[phx-click="toggle"][phx-value-id="#{bad.id}"]|) |> render_click()

      assert html =~ "Sink disabled"
      refute Flux.Sinks.get_sink!(bad.id).enabled
    end
  end
end
