defmodule FluxWeb.SystemSettingsSSOTest do
  # async: false - swaps the global SSO registry and license provider.
  use FluxWeb.ConnCase, async: false

  import Ecto.Query
  import Flux.AccountsFixtures
  import Flux.LicenseHelpers
  import Phoenix.LiveViewTest

  alias Flux.Auth.SSO.{Config, Domain, Registry}

  setup :register_and_log_in_user
  setup :establish_owner_scope

  setup do
    prior_license =
      {Application.get_env(:flux, Flux.License), Application.get_env(:flux, :test_license_tier)}

    original = Registry.active()

    on_exit(fn ->
      reset_license(prior_license)
      Registry.set_active(original)
      Application.delete_env(:flux, :test_sso)
    end)

    :ok
  end

  defp use_sso(cfg \\ %{}) do
    put_license_tier(:enterprise)
    Application.put_env(:flux, :test_sso, Map.put(cfg, :test_pid, self()))
    Registry.set_active(Flux.SSOTestProvider)
  end

  defp configured(attrs \\ []) do
    struct!(
      %Config{
        id: "cfg_test",
        idp_entity_id: "https://idp.acme.test",
        idp_cert_fingerprints: ["ab:cd"],
        sp_entity_id: "#{FluxWeb.Endpoint.url()}/sso/cfg_test/metadata",
        base_url: FluxWeb.Endpoint.url(),
        role_mapping: [{"Flux Admins", "admin"}]
      },
      attrs
    )
  end

  defp verified, do: %Domain{id: 7, domain: "acme.test", verified_at: ~U[2026-01-01 00:00:00Z]}

  defp pending,
    do: %Domain{
      id: 8,
      domain: "acme.test",
      txt_record_name: "_flux-sso.acme.test",
      txt_record_value: "flux-sso-verification=abc"
    }

  test "Community sees an upgrade prompt, not the setup form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/system/settings?tab=sso")

    assert html =~ "sso-upgrade-card"
    refute html =~ ~s(id="sso-config-form")
  end

  test "the tab is deep-linkable and listed", %{conn: conn} do
    use_sso()
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    assert has_element?(lv, ~s(#settings-tab-sso[aria-current="page"]))
    assert has_element?(lv, "#sso-config-form", "Set up SSO")
    refute has_element?(lv, "#sso-domains-card")
  end

  test "saving sends parsed mappings and the deployment URL to the provider", %{conn: conn} do
    use_sso()
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    lv
    |> form("#sso-config-form",
      sso: %{
        idp_metadata: "<EntityDescriptor/>",
        email_attribute: "mail",
        groups_attribute: "",
        role_mapping: "Flux Admins = Admin\nOps = team = viewer\n\n",
        default_role: "viewer"
      }
    )
    |> render_submit()

    assert_received {:sso, :put_config, {_org, attrs, [base_url: base_url]}}
    assert base_url == FluxWeb.Endpoint.url()
    assert attrs["attribute_mapping"] == %{"email" => "mail"}
    assert attrs["role_mapping"] == [{"Flux Admins", "admin"}, {"Ops = team", "viewer"}]
    assert attrs["default_role"] == "viewer"

    assert has_element?(lv, "#sso-entity-id", "/sso/cfg_test/metadata")
    assert has_element?(lv, "#sso-acs-url", "/sso/cfg_test/acs")
  end

  test "a mapping line without a role is refused before reaching the provider", %{conn: conn} do
    use_sso()
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    html =
      lv
      |> form("#sso-config-form", sso: %{idp_metadata: "<x/>", role_mapping: "Just a group"})
      |> render_submit()

    assert html =~ "needs the form Group = role"
    refute_received {:sso, :put_config, _}
  end

  test "provider errors land on the form", %{conn: conn} do
    use_sso(%{put_error: [idp_metadata: "is not valid SAML metadata"]})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    html = lv |> form("#sso-config-form", sso: %{idp_metadata: "nope"}) |> render_submit()

    assert html =~ "is not valid SAML metadata"
  end

  test "a pending domain shows its TXT record, and enforcement waits for verification", %{
    conn: conn
  } do
    use_sso(%{config: configured(domains: [pending()])})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    assert has_element?(lv, "#sso-domain-8", "_flux-sso.acme.test")
    assert has_element?(lv, "#sso-domain-8", "flux-sso-verification=abc")
    assert has_element?(lv, "#sso-enforce-on[disabled]")

    lv |> element("#sso-domain-8 button", "Verify") |> render_click()
    assert_received {:sso, :verify_domain, {_org, "8"}}
  end

  test "adding a domain claims it through the provider", %{conn: conn} do
    use_sso(%{config: configured()})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    lv |> form("#sso-domain-form", sso_domain: %{domain: " acme.test "}) |> render_submit()

    assert_received {:sso, :add_domain, {_org, "acme.test"}}
  end

  test "readiness counts linked non-owner members", %{conn: conn, owner_scope: owner_scope} do
    member = user_fixture()
    {:ok, team} = Flux.Structure.create_team(owner_scope, %{name: "Eng"})

    {:ok, _} =
      Flux.Structure.create_team_member(%{user_id: member.id, team_id: team.id, role: "member"})

    use_sso(%{
      config: configured(domains: [verified()]),
      linked: %{member.id => ~U[2026-11-01 09:00:00Z]}
    })

    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    assert has_element?(lv, "#sso-linked-count", "1")
    assert has_element?(lv, "#sso-member-#{member.id}", "Linked")
  end

  test "requiring SSO asks first, then signs other members out", %{
    conn: conn,
    owner_scope: owner_scope
  } do
    member = user_fixture()
    {:ok, team} = Flux.Structure.create_team(owner_scope, %{name: "Eng"})

    {:ok, _} =
      Flux.Structure.create_team_member(%{user_id: member.id, team_id: team.id, role: "member"})

    Flux.Accounts.generate_user_session_token(member)

    use_sso(%{config: configured(domains: [verified()])})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    lv |> element("#sso-enforce-on") |> render_click()
    assert has_element?(lv, "#sso-enforce-modal", "Everyone except owners is signed out now")
    refute_received {:sso, :set_enforcement, _}

    lv |> element("#sso-enforce-confirm") |> render_click()

    assert_received {:sso, :set_enforcement, {_org, true}}
    assert render(lv) =~ "Members other than owners were signed out"
    assert has_element?(lv, "#sso-enforce-off")

    assert Flux.Repo.aggregate(
             from(t in Flux.Accounts.UserToken,
               where: t.user_id == ^member.id and t.context == "session"
             ),
             :count
           ) == 0
  end

  test "a host change is called out", %{conn: conn} do
    use_sso(%{config: configured(base_url: "https://old.example")})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    assert has_element?(lv, "#sso-host-mismatch", "https://old.example")
  end

  test "removing SSO is confirmed first", %{conn: conn} do
    use_sso(%{config: configured()})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    lv |> element("#sso-delete-button") |> render_click()
    refute_received {:sso, :delete_config, _}

    lv |> element("#sso-delete-confirm") |> render_click()
    assert_received {:sso, :delete_config, _}
    assert has_element?(lv, "#sso-config-form", "Set up SSO")
  end

  test "an owner demoted while the page is open can no longer change SSO",
       %{conn: conn, owner_scope: owner_scope} do
    use_sso(%{config: configured(domains: [verified()])})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    # Ownership moves to someone else; this page stays connected.
    successor = user_fixture()

    from(o in Flux.Structure.Organization, where: o.id == ^owner_scope.organization_id)
    |> Flux.Repo.update_all(set: [user_id: successor.id])

    lv |> element("#sso-enforce-on") |> render_click()
    html = lv |> element("#sso-enforce-confirm") |> render_click()

    assert html =~ "not allowed to manage single sign-on"
    refute_received {:sso, :set_enforcement, _}
  end

  test "a lapsed license between render and submit refuses the write", %{conn: conn} do
    use_sso(%{config: configured(domains: [verified()])})
    {:ok, lv, _html} = live(conn, ~p"/system/settings?tab=sso")

    put_license_tier(:community)
    lv |> element("#sso-enforce-on") |> render_click()
    html = lv |> element("#sso-enforce-confirm") |> render_click()

    assert html =~ "requires Flux Enterprise"
    refute_received {:sso, :set_enforcement, _}
  end

  defp establish_owner_scope(%{user: user}) do
    org =
      Flux.Structure.Organization
      |> where([o], o.user_id == ^user.id)
      |> order_by([o], asc: o.inserted_at)
      |> limit(1)
      |> Flux.Repo.one!()

    %{
      owner_scope: %Flux.Accounts.Scope{
        user: user,
        organization_id: org.id,
        organization_role: "owner"
      }
    }
  end
end
