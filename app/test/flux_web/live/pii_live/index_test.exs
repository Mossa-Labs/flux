defmodule FluxWeb.PIILive.IndexTest do
  # async: false — the :pii_redaction gate swaps the global license provider.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Flux.LicenseHelpers

  describe "community tier (pii_redaction not licensed)" do
    setup [:register_and_log_in_user]

    test "renders the heading and an upgrade prompt without crashing", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/redaction")

      assert html =~ "PII Redaction"
      assert html =~ "View pricing"
    end
  end

  describe "licensed tier (:pii_redaction entitled)" do
    setup [:register_and_log_in_user]

    test "renders the dashboard shell (empty state) when entitled", %{conn: conn} do
      with_license_tier(:enterprise, fn ->
        {:ok, _lv, html} = live(conn, ~p"/redaction")

        assert html =~ "PII Redaction"
        # The default Community PII provider returns the zeroed shape, so the
        # entitled view shows the empty state rather than an upgrade prompt.
        assert html =~ "No redactions yet"
      end)
    end
  end
end
