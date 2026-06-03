defmodule Flux.Accounts.ScopeTest do
  # async: false — sets the global :rbac_mode config and swaps the license provider.
  use Flux.DataCase, async: false

  import Flux.LicenseHelpers

  alias Flux.Accounts
  alias Flux.Accounts.Scope
  alias Flux.AccountsFixtures
  alias Flux.Structure.{Organization, OrganizationMember, Team, TeamMember}

  setup do
    # Org-centric RBAC is requested by config (as EE does); the license gate
    # decides whether it actually takes effect.
    prior = Application.get_env(:flux, :rbac_mode)
    Application.put_env(:flux, :rbac_mode, :org_centric)

    on_exit(fn ->
      if prior,
        do: Application.put_env(:flux, :rbac_mode, prior),
        else: Application.delete_env(:flux, :rbac_mode)
    end)

    :ok
  end

  defp bare_user do
    {:ok, user} = Accounts.register_user(AccountsFixtures.valid_user_attributes())
    user
  end

  defp org_owned_by(owner) do
    Repo.insert!(%Organization{
      name: "Acme",
      slug: "acme-#{System.unique_integer([:positive])}",
      user_id: owner.id
    })
  end

  describe "for_user/1 honors the :org_rbac license gate" do
    setup do
      owner = bare_user()
      member = bare_user()
      org = org_owned_by(owner)

      # Org-centric data: member is a "viewer" via organization_members.
      Repo.insert!(%OrganizationMember{
        organization_id: org.id,
        user_id: member.id,
        role: "viewer"
      })

      # Team-centric data: member is an "admin" via a team in the same org.
      team = Repo.insert!(%Team{name: "Core", organization_id: org.id, user_id: owner.id})
      Repo.insert!(%TeamMember{team_id: team.id, user_id: member.id, role: "admin"})

      %{member: member, org: org}
    end

    test "resolves org-centric (role from membership) when :org_rbac licensed", %{
      member: member,
      org: org
    } do
      with_license_tier(:pro, fn ->
        scope = Scope.for_user(member)
        assert scope.organization_id == org.id
        assert scope.organization_role == "viewer"
      end)
    end

    test "falls back to team-centric (role from team) when :org_rbac NOT licensed", %{
      member: member,
      org: org
    } do
      # Community tier (default): config says org_centric, but the gate forces
      # team_centric, so the role comes from the team membership.
      scope = Scope.for_user(member)
      assert scope.organization_id == org.id
      assert scope.organization_role == "admin"
    end
  end

  describe "user_can_log_in?/1 honors the :org_rbac license gate" do
    setup do
      owner = bare_user()
      org_only = bare_user()
      org = org_owned_by(owner)
      # org_only has ONLY an org membership — no team, owns no org.
      Repo.insert!(%OrganizationMember{
        organization_id: org.id,
        user_id: org_only.id,
        role: "member"
      })

      %{org_only: org_only}
    end

    test "an org-only member can log in when :org_rbac licensed", %{org_only: user} do
      with_license_tier(:pro, fn ->
        assert Scope.user_can_log_in?(user)
      end)
    end

    test "the same member cannot log in unlicensed (gate forces team-centric)", %{org_only: user} do
      # team_centric path needs a team membership or org ownership — this user
      # has neither, so without the org_rbac entitlement they are locked out.
      refute Scope.user_can_log_in?(user)
    end
  end
end
