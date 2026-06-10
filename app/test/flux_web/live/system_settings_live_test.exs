defmodule FluxWeb.SystemSettingsLiveTest do
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Flux.AccountsFixtures

  alias Flux.Structure

  describe "owner access" do
    setup :register_and_log_in_user

    setup %{user: user} do
      # The scope from register_and_log_in_user resolves via team_centric fallback
      # which may pick the wrong org in async tests. We must create a team + membership
      # so that Scope.for_user resolves the user's own org and gets "owner" role.
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

      {:ok, team} = Flux.Structure.create_team(owner_scope, %{name: "Default Team"})

      {:ok, own_membership} =
        Flux.Structure.create_team_member(%{
          user_id: user.id,
          team_id: team.id,
          role: "admin"
        })

      %{team: team, owner_scope: owner_scope, own_membership: own_membership}
    end

    test "owner can access and sees 'System Settings' heading", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "System Settings"
      assert html =~ "Manage teams and users"
    end

    test "shows Teams section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "Teams"
      assert html =~ "New Team"
    end

    test "shows the License section with the current tier", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "License"
      assert html =~ "community"
      assert html =~ "Running the Community tier"
    end

    test "shows Members section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      # In team_centric mode the heading reads "Team members"
      assert html =~ "members"
    end

    test "shows the current user in members list", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ user.email
    end

    test "disables, re-enables, and removes a team member", %{conn: conn, team: team} do
      other = user_fixture()

      {:ok, tm} =
        Structure.create_team_member(%{user_id: other.id, team_id: team.id, role: "member"})

      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      assert render_click(lv, "disable_member", %{
               "id" => to_string(tm.id),
               "kind" => "team_centric"
             }) =~
               "Member disabled."

      assert Structure.get_team_member!(tm.id) |> Flux.Structure.TeamMember.disabled?()

      assert render_click(lv, "enable_member", %{
               "id" => to_string(tm.id),
               "kind" => "team_centric"
             }) =~
               "Member re-enabled."

      refute Structure.get_team_member!(tm.id) |> Flux.Structure.TeamMember.disabled?()

      assert render_click(lv, "remove_member", %{
               "id" => to_string(tm.id),
               "kind" => "team_centric"
             }) =~
               "Member removed."

      assert_raise Ecto.NoResultsError, fn -> Structure.get_team_member!(tm.id) end
    end

    test "refuses to remove your own account", %{conn: conn, own_membership: own} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      assert render_click(lv, "remove_member", %{
               "id" => to_string(own.id),
               "kind" => "team_centric"
             }) =~
               "You cannot remove your own account."

      # The membership is still there.
      assert Structure.get_team_member!(own.id)
    end

    test "shows the API Keys section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "API Keys"
      assert html =~ "No API keys yet."
    end

    test "hides the scope picker without the Pro entitlement", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/system/settings")

      refute has_element?(lv, "#api-key-form select[multiple]")
      assert html =~ "Fine-grained API key scopes"
    end

    test "shows the scope picker with the Pro entitlement", %{conn: conn} do
      Flux.LicenseHelpers.with_license_tier(:pro, fn ->
        {:ok, lv, _html} = live(conn, ~p"/system/settings")
        assert has_element?(lv, "#api-key-form select[multiple]")
      end)
    end

    test "creates an API key and reveals the plaintext once", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      html =
        lv
        |> form("#api-key-form", api_key: %{name: "Production CI", role: "viewer"})
        |> render_submit()

      assert html =~ "Copy this key now"
      assert html =~ "flux_pk_"
      assert html =~ "Production CI"
      assert html =~ "viewer"
    end

    test "revokes an API key", %{conn: conn, user: user} do
      org =
        Flux.Structure.Organization
        |> Ecto.Query.where([o], o.user_id == ^user.id)
        |> Ecto.Query.limit(1)
        |> Flux.Repo.one!()

      {:ok, _raw, key} = Flux.Accounts.create_api_key(org.id, %{name: "to-revoke"})

      {:ok, lv, _html} = live(conn, ~p"/system/settings")
      html = lv |> element("#api-key-#{key.id} button", "Revoke") |> render_click()

      refute html =~ "Revoke"
      assert Flux.Repo.reload(key).revoked_at != nil
    end

    test "hides the Activate Pro form in a Community build", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings")
      refute has_element?(lv, "#activate-license-form")
    end

    test "shows the Activate Pro form when the provider supports activation", %{conn: conn} do
      use_activation_provider()

      {:ok, lv, _html} = live(conn, ~p"/system/settings")
      assert has_element?(lv, "#activate-license-form")
    end

    test "activating a license flashes the restart message", %{conn: conn} do
      use_activation_provider()

      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      html =
        lv
        |> form("#activate-license-form", license: %{token: "a-signed-token"})
        |> render_submit()

      assert html =~ "Pro activated"
      assert html =~ "restart"
    end

    test "renders a near-expiry banner from the license status", %{conn: conn} do
      use_activation_provider()
      soon = DateTime.add(DateTime.utc_now(), 10 * 24 * 3600, :second)

      Application.put_env(:flux, :test_activation_license, %{
        tier: :pro,
        features: [],
        org: "Acme",
        valid_until: soon,
        node_count: 3,
        status: :near_expiry
      })

      {:ok, _lv, html} = live(conn, ~p"/system/settings")
      assert html =~ "Renew soon"
    end
  end

  # Swap in the activation-capable provider for one test, restoring afterwards.
  defp use_activation_provider do
    prev = Application.get_env(:flux, Flux.License)
    Application.put_env(:flux, Flux.License, provider: Flux.LicenseActivationTestProvider)

    ExUnit.Callbacks.on_exit(fn ->
      if prev,
        do: Application.put_env(:flux, Flux.License, prev),
        else: Application.delete_env(:flux, Flux.License)

      Application.delete_env(:flux, :test_activation_license)
    end)
  end
end
