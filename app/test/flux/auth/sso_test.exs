defmodule Flux.Auth.SSOTest do
  # async: false - swaps the global SSO registry and license provider.
  use Flux.DataCase, async: false

  import Flux.AccountsFixtures
  import Flux.LicenseHelpers

  alias Flux.Accounts
  alias Flux.Accounts.{Scope, UserToken}
  alias Flux.Auth.SSO
  alias Flux.Auth.SSO.Registry
  alias Flux.Structure

  setup do
    original = Registry.active()

    on_exit(fn ->
      Registry.set_active(original)
      Application.delete_env(:flux, :test_sso)
    end)

    :ok
  end

  defp use_test_provider(cfg \\ %{}) do
    Application.put_env(:flux, :test_sso, Map.put(cfg, :test_pid, self()))
    Registry.set_active(Flux.SSOTestProvider)
  end

  describe "the Community provider" do
    test "is the default, and SSO is off" do
      assert Registry.active() == SSO.Providers.Community

      with_license_tier(:enterprise, fn ->
        refute SSO.available?()
        assert SSO.discover("a@acme.test") == :none
        assert SSO.password_login_allowed?(user_fixture())

        assert {:error, [{:base, _}]} =
                 SSO.put_config(%Scope{organization_id: 1}, %{}, "http://x")
      end)
    end
  end

  describe "entitlement is re-checked on every call" do
    test "unentitled, a configured provider is ignored entirely" do
      user = user_fixture()
      use_test_provider(%{sso_only: [user.id], config: %SSO.Config{id: "cfg_test"}})

      refute SSO.entitled?()
      refute SSO.available?()
      assert SSO.discover("a@acme.test") == :none
      assert SSO.get_config(1) == nil
      assert SSO.linked_users(1) == %{}
      assert SSO.consume("cfg_test", %{}) == {:error, :enterprise_required}
    end

    test "a lapsed license stops enforcement, so SSO-only members can use passwords again" do
      user = user_fixture()
      use_test_provider(%{sso_only: [user.id]})

      with_license_tier(:enterprise, fn -> refute SSO.password_login_allowed?(user) end)
      assert SSO.password_login_allowed?(user)
    end

    test "writes refuse when unentitled" do
      use_test_provider()
      scope = %Scope{organization_id: 1}

      assert {:error, [{:base, msg}]} = SSO.put_config(scope, %{}, "http://x")
      assert msg =~ "Enterprise"
      assert {:error, _} = SSO.set_enforcement(scope, true)
      assert {:error, _} = SSO.add_domain(scope, "acme.test")
      refute_received {:sso, _, _}
    end
  end

  describe "entitled" do
    setup do
      prior = put_license_tier(:enterprise)
      on_exit(fn -> reset_license(prior) end)
      use_test_provider()
      :ok
    end

    test "discovery trims input and delegates" do
      assert SSO.discover("  pat@acme.test ") == {:ok, "cfg_test"}
      assert SSO.discover("pat@elsewhere.test") == :none
      assert SSO.discover(nil) == :none
    end

    test "put_config passes the base URL for the entity ID" do
      scope = Scope.for_user(user_fixture())

      assert {:ok, config} =
               SSO.put_config(scope, %{"idp_metadata" => "<x/>"}, "https://flux.example")

      assert config.sp_entity_id == "https://flux.example/sso/cfg_test/metadata"
      assert_received {:sso, :put_config, {_, _, [base_url: "https://flux.example"]}}
    end

    test "turning enforcement on signs out every non-owner member, and only them" do
      owner = user_fixture()
      owner_scope = Scope.for_user(owner)
      org_id = owner_scope.organization_id

      org_member = user_fixture()

      {:ok, _} =
        Structure.create_organization_member(%{
          organization_id: org_id,
          user_id: org_member.id,
          role: "admin"
        })

      {:ok, team} = Structure.create_team(owner_scope, %{name: "Data"})
      team_member = user_fixture()

      {:ok, _} =
        Structure.create_team_member(%{user_id: team_member.id, team_id: team.id, role: "member"})

      outsider = user_fixture()

      for u <- [owner, org_member, team_member, outsider],
          do: Accounts.generate_user_session_token(u)

      assert {:ok, %SSO.Config{enforce_sso: true}, revoked} =
               SSO.set_enforcement(owner_scope, true)

      assert revoked |> Enum.map(& &1.user_id) |> Enum.sort() ==
               Enum.sort([org_member.id, team_member.id])

      assert session_count(owner) == 1
      assert session_count(outsider) == 1
      assert session_count(org_member) == 0
      assert session_count(team_member) == 0
    end

    test "turning enforcement off revokes nothing" do
      owner = user_fixture()
      scope = Scope.for_user(owner)

      assert {:ok, %SSO.Config{enforce_sso: false}, []} = SSO.set_enforcement(scope, false)
    end
  end

  defp session_count(user) do
    Repo.aggregate(
      from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"),
      :count
    )
  end
end
