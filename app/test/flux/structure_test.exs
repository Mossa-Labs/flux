defmodule Flux.StructureTest do
  use Flux.DataCase

  alias Flux.Structure

  describe "organizations" do
    alias Flux.Structure.Organization

    import Flux.AccountsFixtures, only: [user_scope_fixture: 0]
    import Flux.StructureFixtures

    @invalid_attrs %{name: nil, slug: nil}

    test "list_organizations/1 returns all scoped organizations" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      organization = organization_fixture(scope)
      other_organization = organization_fixture(other_scope)

      list = Structure.list_organizations(scope)
      assert organization in list
      assert Enum.all?(list, &(&1.user_id == scope.user.id))

      other_list = Structure.list_organizations(other_scope)
      assert other_organization in other_list
      assert Enum.all?(other_list, &(&1.user_id == other_scope.user.id))

      refute organization in other_list
      refute other_organization in list
    end

    test "get_organization!/2 returns the organization with given id" do
      scope = user_scope_fixture()
      organization = organization_fixture(scope)
      other_scope = user_scope_fixture()
      assert Structure.get_organization!(scope, organization.id) == organization

      assert_raise Ecto.NoResultsError, fn ->
        Structure.get_organization!(other_scope, organization.id)
      end
    end

    test "create_organization/2 with valid data creates a organization" do
      valid_attrs = %{name: "some name", slug: "some slug"}
      scope = user_scope_fixture()

      assert {:ok, %Organization{} = organization} =
               Structure.create_organization(scope, valid_attrs)

      assert organization.name == "some name"
      assert organization.slug == "some slug"
      assert organization.user_id == scope.user.id
    end

    test "create_organization/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Structure.create_organization(scope, @invalid_attrs)
    end

    test "update_organization/3 with valid data updates the organization" do
      scope = user_scope_fixture()
      organization = organization_fixture(scope)
      update_attrs = %{name: "some updated name", slug: "some updated slug"}

      assert {:ok, %Organization{} = organization} =
               Structure.update_organization(scope, organization, update_attrs)

      assert organization.name == "some updated name"
      assert organization.slug == "some updated slug"
    end

    test "update_organization/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      organization = organization_fixture(scope)

      assert_raise MatchError, fn ->
        Structure.update_organization(other_scope, organization, %{})
      end
    end

    test "update_organization/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      organization = organization_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Structure.update_organization(scope, organization, @invalid_attrs)

      assert organization == Structure.get_organization!(scope, organization.id)
    end

    test "delete_organization/2 deletes the organization" do
      scope = user_scope_fixture()
      organization = organization_fixture(scope)
      assert {:ok, %Organization{}} = Structure.delete_organization(scope, organization)

      assert_raise Ecto.NoResultsError, fn ->
        Structure.get_organization!(scope, organization.id)
      end
    end

    test "delete_organization/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      organization = organization_fixture(scope)
      assert_raise MatchError, fn -> Structure.delete_organization(other_scope, organization) end
    end

    test "change_organization/2 returns a organization changeset" do
      scope = user_scope_fixture()
      organization = organization_fixture(scope)
      assert %Ecto.Changeset{} = Structure.change_organization(scope, organization)
    end
  end

  describe "teams" do
    alias Flux.Structure.Team

    import Flux.AccountsFixtures, only: [user_scope_fixture: 0]
    import Flux.StructureFixtures

    @invalid_attrs %{name: nil}

    test "list_teams/1 returns all scoped teams" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      team = team_fixture(scope)
      other_team = team_fixture(other_scope)
      # With org-scoped list_teams, when both scopes share the same org they see the same teams
      teams = Structure.list_teams(scope)
      assert team in teams
      assert other_team in teams
      assert teams == Structure.list_teams(other_scope)
    end

    test "get_team!/2 returns the team with given id" do
      scope = user_scope_fixture()
      team = team_fixture(scope)
      other_scope = user_scope_fixture()
      assert Structure.get_team!(scope, team.id) == team
      # Scope with a different org cannot see the team
      other_org = organization_fixture(other_scope)
      other_org_scope = %{other_scope | organization_id: other_org.id}

      assert_raise Ecto.NoResultsError, fn ->
        Structure.get_team!(other_org_scope, team.id)
      end
    end

    test "create_team/2 with valid data creates a team" do
      valid_attrs = %{name: "some name"}
      scope = user_scope_fixture()

      assert {:ok, %Team{} = team} = Structure.create_team(scope, valid_attrs)
      assert team.name == "some name"
      assert team.user_id == scope.user.id
    end

    test "create_team/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Structure.create_team(scope, @invalid_attrs)
    end

    test "update_team/3 with valid data updates the team" do
      scope = user_scope_fixture()
      team = team_fixture(scope)
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Team{} = team} = Structure.update_team(scope, team, update_attrs)
      assert team.name == "some updated name"
    end

    test "update_team/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      team = team_fixture(scope)

      assert_raise MatchError, fn ->
        Structure.update_team(other_scope, team, %{})
      end
    end

    test "update_team/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      team = team_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Structure.update_team(scope, team, @invalid_attrs)
      assert team == Structure.get_team!(scope, team.id)
    end

    test "delete_team/2 deletes the team" do
      scope = user_scope_fixture()
      team = team_fixture(scope)
      assert {:ok, %Team{}} = Structure.delete_team(scope, team)
      assert_raise Ecto.NoResultsError, fn -> Structure.get_team!(scope, team.id) end
    end

    test "delete_team/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      team = team_fixture(scope)
      assert_raise MatchError, fn -> Structure.delete_team(other_scope, team) end
    end

    test "change_team/2 returns a team changeset" do
      scope = user_scope_fixture()
      team = team_fixture(scope)
      assert %Ecto.Changeset{} = Structure.change_team(scope, team)
    end
  end

  describe "team_members" do
    alias Flux.Structure.TeamMember

    import Flux.StructureFixtures

    @invalid_attrs %{role: nil}

    test "list_team_members/0 returns all team_members" do
      team_member = team_member_fixture()
      assert Structure.list_team_members() == [team_member]
    end

    test "get_team_member!/1 returns the team_member with given id" do
      team_member = team_member_fixture()
      assert Structure.get_team_member!(team_member.id) == team_member
    end

    test "create_team_member/1 with valid data creates a team_member" do
      scope = Flux.AccountsFixtures.user_scope_fixture()
      _org = organization_fixture(scope)
      team = team_fixture(scope)
      valid_attrs = %{role: "member", user_id: scope.user.id, team_id: team.id}

      assert {:ok, %TeamMember{} = team_member} = Structure.create_team_member(valid_attrs)
      assert team_member.role == "member"
    end

    test "create_team_member/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Structure.create_team_member(@invalid_attrs)
    end

    test "update_team_member/2 with valid data updates the team_member" do
      team_member = team_member_fixture()
      update_attrs = %{role: "admin"}

      assert {:ok, %TeamMember{} = team_member} =
               Structure.update_team_member(team_member, update_attrs)

      assert team_member.role == "admin"
    end

    test "update_team_member/2 with invalid data returns error changeset" do
      team_member = team_member_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Structure.update_team_member(team_member, @invalid_attrs)

      assert team_member == Structure.get_team_member!(team_member.id)
    end

    test "delete_team_member/1 deletes the team_member" do
      team_member = team_member_fixture()
      assert {:ok, %TeamMember{}} = Structure.delete_team_member(team_member)
      assert_raise Ecto.NoResultsError, fn -> Structure.get_team_member!(team_member.id) end
    end

    test "change_team_member/1 returns a team_member changeset" do
      team_member = team_member_fixture()
      assert %Ecto.Changeset{} = Structure.change_team_member(team_member)
    end
  end
end
