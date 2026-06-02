defmodule FluxWeb.SystemSettingsLiveTest do
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

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

      {:ok, _tm} =
        Flux.Structure.create_team_member(%{
          user_id: user.id,
          team_id: team.id,
          role: "admin"
        })

      :ok
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

    test "shows Members section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      # In team_centric mode the heading reads "Team members"
      assert html =~ "members"
    end

    test "shows the current user in members list", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ user.email
    end
  end
end
