defmodule FluxWeb.SystemSettingsAuthorizationTest do
  # async: false: switches :rbac_mode and the license provider for org-centric tests.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Flux.AccountsFixtures
  import Flux.LicenseHelpers

  alias Flux.Repo
  alias Flux.Structure
  alias Flux.Structure.{Organization, OrganizationMember, TeamMember}

  # System Settings must act only inside the caller's own organization, and only
  # for a caller who may manage it. Hiding a button is not an access control:
  # anyone holding the page's live socket can push any event with any params,
  # including a visitor who was shown the 403.

  describe "an owner in team-centric mode" do
    setup :register_and_log_in_user
    setup :establish_owner_scope

    test "can't remove, disable or re-enable another organization's members", %{conn: conn} do
      active = foreign_org_member()
      disabled = foreign_org_member(disabled: true)
      foreign_team_member = foreign_team_member()

      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      for kind <- ~w(org_centric team_centric) do
        render_click(lv, "remove_member", %{"id" => to_string(active.id), "kind" => kind})
        render_click(lv, "disable_member", %{"id" => to_string(active.id), "kind" => kind})
        render_click(lv, "enable_member", %{"id" => to_string(disabled.id), "kind" => kind})

        render_click(lv, "remove_member", %{
          "id" => to_string(foreign_team_member.id),
          "kind" => kind
        })
      end

      assert %OrganizationMember{disabled_at: nil} = Repo.reload(active)
      assert %OrganizationMember{disabled_at: %DateTime{}} = Repo.reload(disabled)
      assert %TeamMember{} = Repo.reload(foreign_team_member)
    end

    test "can't change the role of another organization's member", %{conn: conn} do
      foreign = foreign_org_member()
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      render_click(lv, "edit_member", %{"id" => to_string(foreign.id), "kind" => "org_centric"})
      render_click(lv, "save_member", %{"member" => %{"role" => "owner"}})

      assert Repo.reload(foreign).role == "member"
    end

    test "can't revoke another organization's API key", %{conn: conn} do
      other_org = own_org(user_fixture())
      {:ok, _raw, key} = Flux.Accounts.create_api_key(other_org.id, %{name: "theirs"})

      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=api-keys")
      render_click(lv, "revoke_api_key", %{"id" => to_string(key.id)})

      assert Repo.reload(key).revoked_at == nil
    end

    test "still manages their own organization's team members", %{conn: conn, team: team} do
      colleague = user_fixture()

      {:ok, tm} =
        Structure.create_team_member(%{user_id: colleague.id, team_id: team.id, role: "member"})

      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      # The page ignores a client-supplied kind and uses the server's RBAC mode.
      assert render_click(lv, "disable_member", %{
               "id" => to_string(tm.id),
               "kind" => "org_centric"
             }) =~ "Member disabled."

      assert TeamMember.disabled?(Repo.reload(tm))
    end

    test "edits the role of their own organization's team member", %{conn: conn, team: team} do
      colleague = user_fixture()

      {:ok, tm} =
        Structure.create_team_member(%{user_id: colleague.id, team_id: team.id, role: "member"})

      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")
      render_click(lv, "edit_member", %{"id" => to_string(tm.id)})

      assert render_click(lv, "save_member", %{
               "member" => %{"role" => "admin", "team_id" => to_string(team.id)}
             }) =~ "Member updated."

      assert Repo.reload(tm).role == "admin"
    end

    test "can't change the role of another organization's team member", %{conn: conn} do
      foreign = foreign_team_member()
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      assert render_click(lv, "edit_member", %{"id" => to_string(foreign.id)}) =~
               "Member not found."

      render_click(lv, "save_member", %{"member" => %{"role" => "owner"}})

      assert Repo.reload(foreign).role == "member"
    end
  end

  describe "a visitor who may not view System Settings" do
    setup do
      owner = user_fixture()
      org = own_org(owner)
      owner_scope = owner_scope(owner, org)
      {:ok, team} = Structure.create_team(owner_scope, %{name: "Ops"})

      viewer = user_fixture()
      colleague = user_fixture()

      {:ok, _} =
        Structure.create_team_member(%{user_id: viewer.id, team_id: team.id, role: "viewer"})

      {:ok, colleague_tm} =
        Structure.create_team_member(%{user_id: colleague.id, team_id: team.id, role: "member"})

      %{conn: log_in_user(build_conn(), viewer), org: org, colleague_tm: colleague_tm}
    end

    test "can't act on members through the live socket", %{conn: conn, colleague_tm: tm} do
      {:ok, lv, html} = live(conn, ~p"/system/settings?tab=members")
      assert html =~ "403 Forbidden"

      render_click(lv, "disable_member", %{"id" => to_string(tm.id), "kind" => "team_centric"})
      render_click(lv, "remove_member", %{"id" => to_string(tm.id), "kind" => "team_centric"})

      assert %TeamMember{} = reloaded = Repo.reload(tm)
      refute TeamMember.disabled?(reloaded)
    end

    test "can't create an API key through the live socket", %{conn: conn, org: org} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=api-keys")

      render_click(lv, "create_api_key", %{"api_key" => %{"name" => "sneaky"}})

      assert Flux.Accounts.list_api_keys(org.id) == []
    end
  end

  describe "an owner in org-centric mode" do
    setup :use_org_centric_mode
    setup :register_and_log_in_user

    setup %{user: user} do
      org = own_org(user)

      assert %OrganizationMember{role: "owner"} =
               Structure.get_organization_member(org.id, user.id)

      %{org: org}
    end

    test "changes the role of a member of their own organization", %{conn: conn, org: org} do
      colleague = org_member(org, user_fixture(), "member")
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      render_click(lv, "edit_member", %{"id" => to_string(colleague.id), "kind" => "org_centric"})

      assert render_click(lv, "save_member", %{"member" => %{"role" => "admin"}}) =~
               "Member updated."

      assert Repo.reload(colleague).role == "admin"
    end

    test "can't remove or re-role another organization's member", %{conn: conn} do
      foreign = foreign_org_member()
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      render_click(lv, "remove_member", %{"id" => to_string(foreign.id), "kind" => "org_centric"})
      render_click(lv, "edit_member", %{"id" => to_string(foreign.id), "kind" => "org_centric"})
      render_click(lv, "save_member", %{"member" => %{"role" => "owner"}})

      assert %OrganizationMember{role: "member"} = Repo.reload(foreign)
    end

    test "loses member management as soon as they are demoted, even with the page open", %{
      conn: conn,
      org: org,
      user: user
    } do
      colleague = org_member(org, user_fixture(), "member")
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      {:ok, _} =
        Structure.update_organization_member(
          Structure.get_organization_member(org.id, user.id),
          %{role: "member"}
        )

      render_click(lv, "remove_member", %{
        "id" => to_string(colleague.id),
        "kind" => "org_centric"
      })

      own = Structure.get_organization_member(org.id, user.id)
      render_click(lv, "edit_member", %{"id" => to_string(own.id), "kind" => "org_centric"})
      render_click(lv, "save_member", %{"member" => %{"role" => "owner"}})

      assert %OrganizationMember{} = Repo.reload(colleague)
      assert Repo.reload(own).role == "member"
    end

    # An admin may manage members elsewhere, but this page is owner-only: an
    # owner demoted to admin must not use their open page to undo the demotion.
    test "loses the whole page as soon as they are demoted to admin", %{
      conn: conn,
      org: org,
      user: user
    } do
      other_owner = org_member(org, user_fixture(), "owner")
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      own = Structure.get_organization_member(org.id, user.id)
      {:ok, _} = Structure.update_organization_member(own, %{role: "admin"})

      render_click(lv, "edit_member", %{"id" => to_string(own.id)})
      render_click(lv, "save_member", %{"member" => %{"role" => "owner"}})
      render_click(lv, "remove_member", %{"id" => to_string(other_owner.id)})
      render_click(lv, "create_api_key", %{"api_key" => %{"name" => "backdoor"}})
      render_click(lv, "save_team", %{"team" => %{"name" => "Shadow"}})

      assert Repo.reload(own).role == "admin"
      assert %OrganizationMember{role: "owner"} = Repo.reload(other_owner)
      assert Flux.Accounts.list_api_keys(org.id) == []
      refute Repo.exists?(from t in Flux.Structure.Team, where: t.name == "Shadow")
    end
  end

  describe "malformed member ids" do
    setup :register_and_log_in_user
    setup :establish_owner_scope

    test "are refused without crashing the page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=members")

      for id <- ["1abc", "", "-", "99999999999999999999"] do
        assert render_click(lv, "remove_member", %{"id" => id}) =~ "Member not found."
      end
    end
  end

  # A membership row in an organization the test user does not belong to.
  defp foreign_org_member(opts \\ []) do
    org = own_org(user_fixture())
    member = org_member(org, user_fixture(), "member")

    if opts[:disabled] do
      {:ok, member} = Structure.disable_organization_member(member)
      member
    else
      member
    end
  end

  defp foreign_team_member do
    other_owner = user_fixture()
    org = own_org(other_owner)
    {:ok, team} = Structure.create_team(owner_scope(other_owner, org), %{name: "Theirs"})

    {:ok, tm} =
      Structure.create_team_member(%{
        user_id: user_fixture().id,
        team_id: team.id,
        role: "member"
      })

    tm
  end

  defp org_member(%Organization{id: org_id}, user, role) do
    {:ok, member} =
      Structure.create_organization_member(%{
        organization_id: org_id,
        user_id: user.id,
        role: role
      })

    member
  end

  defp own_org(user) do
    Organization
    |> where([o], o.user_id == ^user.id)
    |> order_by([o], asc: o.inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  defp owner_scope(user, %Organization{id: org_id}) do
    %Flux.Accounts.Scope{user: user, organization_id: org_id, organization_role: "owner"}
  end

  # Same setup as SystemSettingsLiveTest: a team + membership makes
  # Scope.for_user resolve the user's own organization with the "owner" role.
  defp establish_owner_scope(%{user: user}) do
    org = own_org(user)
    {:ok, team} = Structure.create_team(owner_scope(user, org), %{name: "Default Team"})

    {:ok, _own} =
      Structure.create_team_member(%{user_id: user.id, team_id: team.id, role: "admin"})

    %{team: team}
  end

  defp use_org_centric_mode(_context) do
    prior_mode = Application.get_env(:flux, :rbac_mode)
    prior_license = put_license_tier(:pro)
    Application.put_env(:flux, :rbac_mode, :org_centric)

    on_exit(fn ->
      reset_license(prior_license)

      if prior_mode,
        do: Application.put_env(:flux, :rbac_mode, prior_mode),
        else: Application.delete_env(:flux, :rbac_mode)
    end)

    :ok
  end
end
