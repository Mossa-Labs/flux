defmodule FluxWeb.AlertsLive.IndexTest do
  # async: false — the :alerting gate swaps the global license provider / registry.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Flux.LicenseHelpers

  # Resolve the logged-in user to "owner" of their own org so the owner-only
  # gate passes (mirrors DLQLiveTest / SystemSettingsLiveTest).
  defp make_owner(%{user: user}) do
    org =
      Flux.Structure.Organization
      |> where([o], o.user_id == ^user.id)
      |> order_by([o], asc: o.inserted_at)
      |> limit(1)
      |> Flux.Repo.one!()

    owner_scope = %Flux.Accounts.Scope{
      user: user,
      organization_id: org.id,
      organization_role: "owner"
    }

    {:ok, _team} = Flux.Structure.create_team(owner_scope, %{name: "Default Team"})
    {:ok, org_id: org.id}
  end

  describe "owner on the community tier (alerting not licensed)" do
    setup [:register_and_log_in_user, :make_owner]

    test "shows the heading and an upgrade prompt, no rule form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/alerts")

      assert html =~ "Alerts"
      assert html =~ "Alerting &amp; notifications is a Flux Pro feature"
      assert html =~ "View pricing"
      refute html =~ "New rule"
    end
  end

  describe "owner on a licensed tier (:alerting entitled)" do
    setup [:register_and_log_in_user, :make_owner]

    setup do
      state = put_license_tier(:pro)
      Flux.AlertsTestProvider.reset()
      Flux.Alerts.Registry.set_active(Flux.AlertsTestProvider)

      on_exit(fn ->
        Flux.Alerts.Registry.set_active(Flux.Alerts.Providers.Community)
        reset_license(state)
      end)

      :ok
    end

    test "shows the empty state and the New rule action", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/alerts")

      assert html =~ "No alert rules yet"
      assert html =~ "New rule"
      refute html =~ "View pricing"
    end

    test "creates a rule end-to-end through the facade", %{conn: conn, org_id: org_id} do
      {:ok, lv, _html} = live(conn, ~p"/system/alerts")

      lv |> element("button", "New rule") |> render_click()

      html =
        lv
        |> form("#alert-rule-form", %{
          "rule" => %{
            "name" => "Payments failure spike",
            "trigger_type" => "failure_rate",
            "threshold" => "0.05",
            "cooldown_minutes" => "10",
            "webhook_url" => "https://example.com/hook"
          }
        })
        |> render_submit()

      assert html =~ "Alert rule saved."
      assert html =~ "Payments failure spike"

      assert [%{name: "Payments failure spike", channels: [%{"type" => "webhook"}]}] =
               Flux.AlertsTestProvider.list_rules(org_id)
    end
  end
end
