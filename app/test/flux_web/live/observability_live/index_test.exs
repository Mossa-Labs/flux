defmodule FluxWeb.ObservabilityLive.IndexTest do
  # async: false — the :observability gate swaps the global license provider / registry.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Flux.LicenseHelpers

  describe "community tier (observability not licensed)" do
    setup [:register_and_log_in_user]

    test "shows the heading and an upgrade prompt", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/observability")

      assert html =~ "Observability"
      assert html =~ "is a Flux Pro feature"
      assert html =~ "View pricing"
    end
  end

  describe "licensed tier (:observability entitled)" do
    setup [:register_and_log_in_user]

    setup %{scope: scope} do
      org_id = scope.organization_id
      state = put_license_tier(:pro)

      Flux.ObservabilityTestProvider.reset(
        health: %{
          org_id => [
            %{
              source: "github",
              freshness: %{
                state: :ok,
                last_seen_at: DateTime.utc_now(),
                expected_interval_seconds: 900,
                age_seconds: 12
              },
              volume: %{
                state: :ok,
                current_rate: 5,
                baseline_rate: 4.8
              },
              schema: %{state: :ok, fingerprint: 123, field_count: 4, last_drift_at: nil}
            }
          ]
        }
      )

      Flux.Observability.Registry.set_active(Flux.ObservabilityTestProvider)

      on_exit(fn ->
        Flux.Observability.Registry.set_active(Flux.Observability.Providers.Community)
        reset_license(state)
      end)

      {:ok, org_id: org_id}
    end

    test "renders the source health card, no upgrade prompt", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/observability")

      assert html =~ "github"
      assert html =~ "Freshness"
      assert html =~ "Volume"
      assert html =~ "Schema"
      refute html =~ "View pricing"
    end

    test "saves a freshness SLO through the facade", %{conn: conn, org_id: org_id} do
      {:ok, lv, _html} = live(conn, ~p"/observability")

      html =
        lv
        |> form("#observability-source-github form", %{
          "slo" => %{"source" => "github", "expected_interval_seconds" => "600"}
        })
        |> render_submit()

      assert html =~ "Freshness SLO saved for github."

      assert {:ok, %{expected_interval_seconds: 600}} =
               Flux.ObservabilityTestProvider.get_slo(org_id, "github")
    end
  end
end
