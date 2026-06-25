defmodule FluxWeb.SinkLive.FormProTest do
  # async: false — exercises the Pro-licensed render path by swapping the global
  # license provider via Flux.LicenseHelpers (see DLQLive.IndexTest for the pattern).
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Flux.LicenseHelpers

  setup :register_and_log_in_user

  setup do
    state = put_license_tier(:pro)
    on_exit(fn -> reset_license(state) end)
    :ok
  end

  describe "Pro-gated sink types under a licensed tier" do
    test "selecting BigQuery renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "bigquery"})

      assert html =~ "Project ID"
      assert html =~ "Service Account JSON"
      refute html =~ "is a Flux Pro feature"
    end

    test "selecting Snowflake renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "snowflake"})

      assert html =~ "Account Identifier"
      assert html =~ "Warehouse"
      assert html =~ "Private Key (PEM)"
      refute html =~ "is a Flux Pro feature"
    end
  end
end
