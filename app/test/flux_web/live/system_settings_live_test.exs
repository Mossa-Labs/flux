defmodule FluxWeb.SystemSettingsLiveTest do
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Flux.AccountsFixtures

  alias Flux.Structure

  describe "owner access" do
    setup :register_and_log_in_user
    setup :establish_owner_scope

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

    test "shows the IP Allowlist section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")
      assert html =~ "IP Allowlist"
    end

    test "saves a valid allowlist and persists it", %{conn: conn, owner_scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      html =
        lv
        |> form("#ip-allowlist-form", security: %{ip_allowlist: "10.0.0.0/8\n1.2.3.4"})
        |> render_submit()

      assert html =~ "IP allowlist updated."

      assert Flux.Security.get_settings(scope.organization_id).ip_allowlist == [
               "10.0.0.0/8",
               "1.2.3.4/32"
             ]
    end

    test "shows an inline error for an invalid CIDR and does not persist", %{
      conn: conn,
      owner_scope: scope
    } do
      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      html =
        lv
        |> form("#ip-allowlist-form", security: %{ip_allowlist: "not-a-cidr"})
        |> render_submit()

      assert html =~ "invalid CIDR"
      assert Flux.Security.get_settings(scope.organization_id).ip_allowlist == []
    end

    test "saves the session timeout", %{conn: conn, owner_scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      html =
        lv
        |> form("#session-timeout-form", security: %{session_timeout_minutes: "1440"})
        |> render_submit()

      assert html =~ "Session timeout updated."
      assert Flux.Security.get_settings(scope.organization_id).session_timeout_minutes == 1440
    end

    test "shows the password policy upgrade prompt without the Enterprise entitlement", %{
      conn: conn
    } do
      {:ok, lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "Password policy"
      # Community build: locked — prompt shown, editable form absent.
      assert html =~ "Password policies"
      refute has_element?(lv, "#password-policy-form")
    end

    test "shows the editable password policy form with the Enterprise entitlement", %{conn: conn} do
      Flux.LicenseHelpers.with_license_tier(:enterprise, fn ->
        {:ok, lv, _html} = live(conn, ~p"/system/settings")
        assert has_element?(lv, "#password-policy-form")
      end)
    end

    test "saves a valid password policy and persists it", %{conn: conn, owner_scope: scope} do
      Flux.LicenseHelpers.with_license_tier(:enterprise, fn ->
        {:ok, lv, _html} = live(conn, ~p"/system/settings")

        html =
          lv
          |> form("#password-policy-form",
            security: %{
              password_min_length: "16",
              password_require_upper: "true",
              password_require_number: "true",
              password_rotation_days: "90"
            }
          )
          |> render_submit()

        assert html =~ "Password policy updated."

        settings = Flux.Security.get_settings(scope.organization_id)
        assert settings.password_min_length == 16
        assert settings.password_require_upper
        assert settings.password_require_number
        refute settings.password_require_special
        assert settings.password_rotation_days == 90
      end)
    end

    test "rejects a password policy below the min-12 floor", %{conn: conn, owner_scope: scope} do
      Flux.LicenseHelpers.with_license_tier(:enterprise, fn ->
        {:ok, lv, _html} = live(conn, ~p"/system/settings")

        html =
          lv
          |> form("#password-policy-form", security: %{password_min_length: "8"})
          |> render_submit()

        assert html =~ "Password min length"
        assert Flux.Security.get_settings(scope.organization_id).password_min_length == 12
      end)
    end

    test "shows the MFA enforcement upgrade prompt without the Enterprise entitlement", %{
      conn: conn
    } do
      {:ok, lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "Require two-factor authentication"
      # Community build: locked — prompt shown, editable form absent.
      assert html =~ "Require MFA for all members"
      refute has_element?(lv, "#mfa-enforcement-form")
    end

    test "shows and saves the MFA enforcement toggle with the Enterprise entitlement", %{
      conn: conn,
      owner_scope: scope
    } do
      Flux.LicenseHelpers.with_license_tier(:enterprise, fn ->
        {:ok, lv, _html} = live(conn, ~p"/system/settings")
        assert has_element?(lv, "#mfa-enforcement-form")

        html =
          lv
          |> form("#mfa-enforcement-form", security: %{require_mfa: "true"})
          |> render_submit()

        assert html =~ "MFA enforcement updated."
        assert Flux.Security.get_settings(scope.organization_id).require_mfa
      end)
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

      assert html =~ "Pro license applied"
      # Feature gating flips at once but services are wired at boot, so the
      # operator has to be told the change is not fully live yet.
      assert html =~ "restart"
    end

    test "on a cluster the message names every node that needs restarting", %{conn: conn} do
      use_activation_provider()

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :pro, license_id: "lic-1", valid_until: nil},
        %{node: :"flux@10.0.0.2", tier: :community, license_id: nil, valid_until: nil}
      ])

      on_exit(fn -> Application.delete_env(:flux, :test_node_states) end)

      {:ok, lv, html} = live(conn, ~p"/system/settings")

      # Per-node state is shown, and the divergence is called out — "applied" on
      # the node that served the form says nothing about the others.
      assert html =~ "flux@10.0.0.1"
      assert html =~ "flux@10.0.0.2"
      assert html =~ "Not yet consistent"

      applied =
        lv
        |> form("#activate-license-form", license: %{token: "a-signed-token"})
        |> render_submit()

      assert applied =~ "restart every Flux node"
    end

    test "tells a single visible node to restart every node anyway", %{conn: conn} do
      use_activation_provider()

      # THE REGRESSION TEST. This used to say "restart the node", singular, and it
      # said it precisely when it was most wrong: cluster formation is a licensed
      # capability, so a multi-node deployment being licensed for the first time
      # has not clustered yet and reports exactly one node. The operator would
      # restart one of three and wonder why nothing changed.
      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :enterprise, license_id: "abc", valid_until: nil}
      ])

      {:ok, lv, _} = live(conn, ~p"/system/settings")

      applied =
        lv
        |> form("#activate-license-form", license: %{token: "a-signed-token"})
        |> render_submit()

      assert applied =~ "restart every Flux node"
      refute applied =~ "restart the node to finish"
    end

    test "says so when fewer nodes are reachable than are licensed", %{conn: conn} do
      use_activation_provider()

      # Licensed for 3, only 1 has restarted and joined. Previously the table hid
      # itself at one row, so this said nothing at all — the operator had no way to
      # tell "my other nodes have not picked this up" from "everything is fine".
      Application.put_env(:flux, :test_activation_license, %{
        tier: :enterprise,
        features: [],
        org: "Acme",
        valid_until: nil,
        node_count: 3,
        status: :active
      })

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :enterprise, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "Licensed for 3 nodes"
      assert html =~ "1 currently reachable"
    end

    test "stays quiet for a single-node license on a single node", %{conn: conn} do
      use_activation_provider()

      # No shortfall and nothing to compare, so the table would be pure noise —
      # the badge above already reports this node's tier.
      Application.put_env(:flux, :test_activation_license, %{
        tier: :pro,
        features: [],
        org: "Acme",
        valid_until: nil,
        node_count: 1,
        status: :active
      })

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :pro, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      refute html =~ "currently reachable"
      refute html =~ ~s(id="cluster-license-state")
    end

    test "an unlimited license never reports a shortfall", %{conn: conn} do
      use_activation_provider()

      # node_count nil means unlimited. A naive `node_count > length(...)` would
      # compare nil and blow up, or treat it as zero and hide the table forever.
      Application.put_env(:flux, :test_activation_license, %{
        tier: :enterprise,
        features: [],
        org: "Acme",
        valid_until: nil,
        node_count: nil,
        status: :active
      })

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :enterprise, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      refute html =~ "currently reachable"
    end

    test "an unreachable node is reported as such, not as unlicensed", %{conn: conn} do
      use_activation_provider()

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :pro, license_id: "lic-1", valid_until: nil},
        %{node: :"flux@10.0.0.2", tier: :unreachable, license_id: nil, valid_until: nil}
      ])

      on_exit(fn -> Application.delete_env(:flux, :test_node_states) end)

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      # During a rolling restart "we could not ask" and "it has no license" send
      # the operator in different directions.
      assert html =~ "unreachable"
    end

    # The counts and the over/under verdict come from the provider, never from a
    # comparison made in the LiveView — so these tests set the VERDICT, not two
    # numbers for the page to compare. A test that set `live: 3, licensed: 2` and
    # expected the warning would be asserting the wrong thing: it would pass just
    # as happily against a UI that had reinvented the threshold locally.
    test "says so when more nodes are running than are licensed", %{conn: conn} do
      use_activation_provider()

      Application.put_env(:flux, :test_node_capacity, %{live: 3, licensed: 2, over?: true})

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :enterprise, license_id: "abc", valid_until: nil},
        %{node: :"flux@10.0.0.2", tier: :enterprise, license_id: "abc", valid_until: nil},
        %{node: :"flux@10.0.0.3", tier: :enterprise, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "Running 3 nodes on a license for 2"
      assert html =~ "3 of 2"
    end

    # The anti-false-alarm test. A cluster sitting exactly at its limit is the
    # normal state of a correctly-licensed deployment, and it is also the state a
    # rolling restart passes through — so a warning here would fire on precisely
    # the deployments that are behaving correctly. This case must stay silent.
    test "an at-limit cluster is not reported as over", %{conn: conn} do
      use_activation_provider()

      Application.put_env(:flux, :test_node_capacity, %{live: 2, licensed: 2, over?: false})

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :enterprise, license_id: "abc", valid_until: nil},
        %{node: :"flux@10.0.0.2", tier: :enterprise, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      refute html =~ "unsupported configuration"
      refute html =~ "Running 2 nodes on a license for"
      # The counts are still shown — knowing you are at 2 of 2 is what tells an
      # operator whether they may add another node.
      assert html =~ "2 of 2"
    end

    test "reports nothing about capacity when the provider has no cap", %{conn: conn} do
      use_activation_provider()

      # `node_capacity/0` returning nil is both "this build does not cap nodes"
      # and "this license is uncapped". Neither is worth a warning, and neither
      # should print a count against an unknown denominator.
      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :enterprise, license_id: "abc", valid_until: nil},
        %{node: :"flux@10.0.0.2", tier: :enterprise, license_id: "abc", valid_until: nil},
        %{node: :"flux@10.0.0.3", tier: :enterprise, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      refute html =~ "unsupported configuration"
      refute html =~ "on a license for"
      # The roster itself still renders — three nodes is worth seeing.
      assert html =~ ~s(id="cluster-license-state")
    end

    test "an over-capacity single node still surfaces the notice", %{conn: conn} do
      use_activation_provider()

      # Guards against tying the notice to `length(node_states) > 1`. A one-node
      # license breached by a second node that this node cannot yet reach still
      # leaves the roster at one row.
      Application.put_env(:flux, :test_node_capacity, %{live: 2, licensed: 1, over?: true})

      Application.put_env(:flux, :test_node_states, [
        %{node: :"flux@10.0.0.1", tier: :pro, license_id: "abc", valid_until: nil}
      ])

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "Running 2 nodes on a license for 1"
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
  describe "branding" do
    setup :register_and_log_in_user
    setup :establish_owner_scope

    setup do
      # put_license_tier/1 does NOT restore itself — it hands back the prior state
      # to pair with reset_license/1. Without this the tier leaks into every later
      # test in the run, which is how the Community case below started seeing an
      # Enterprise form.
      prior_license =
        {Application.get_env(:flux, Flux.License), Application.get_env(:flux, :test_license_tier)}

      on_exit(fn ->
        Flux.LicenseHelpers.reset_license(prior_license)
        Flux.Branding.Registry.set_active(Flux.Branding.Providers.Community)
        Application.delete_env(:flux, :test_branding_theme)
      end)
    end

    defp use_branding_provider(theme) do
      Application.put_env(:flux, :test_branding_theme, theme)
      Flux.Branding.Registry.set_active(Flux.BrandingTestProvider)
    end

    test "Community sees an upgrade prompt, not a form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ "White-label branding"
      refute html =~ ~s(id="branding-form")
    end

    test "an entitled deployment gets the form, seeded with current branding", %{conn: conn} do
      Flux.LicenseHelpers.put_license_tier(:enterprise)
      use_branding_provider(%Flux.Branding.Theme{brand_name: "Acme", primary_color: "#ff0000"})

      {:ok, _lv, html} = live(conn, ~p"/system/settings")

      assert html =~ ~s(id="branding-form")
      assert html =~ "Acme"
      assert html =~ "#ff0000"
    end

    test "saving reports that colours need a reload", %{conn: conn} do
      # The chrome re-reads branding only on a full page load, so a flash that
      # implied it had already changed everywhere would be a small lie.
      Flux.LicenseHelpers.put_license_tier(:enterprise)
      use_branding_provider(%Flux.Branding.Theme{brand_name: "Acme"})

      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      html =
        lv
        |> form("#branding-form", branding: %{brand_name: "Acme", primary_color: "#112233"})
        |> render_submit()

      assert html =~ "Reload"
    end

    test "a lapsed entitlement refuses the write even with the form posted", %{conn: conn} do
      # The section is hidden on Community, but hiding a form is not an access
      # control — the event can still be pushed over the socket.
      Flux.LicenseHelpers.put_license_tier(:enterprise)
      use_branding_provider(%Flux.Branding.Theme{brand_name: "Acme"})
      {:ok, lv, _html} = live(conn, ~p"/system/settings")

      Flux.LicenseHelpers.put_license_tier(:community)

      html =
        lv
        |> with_target("#branding-form")
        |> render_submit("save_branding", %{branding: %{brand_name: "Pirate"}})

      assert html =~ "requires Flux Enterprise"
    end
  end

  # The scope from register_and_log_in_user resolves via the team_centric fallback,
  # which may pick the wrong org in async tests. Creating a team + membership makes
  # Scope.for_user resolve the user's own org with the "owner" role.
  defp establish_owner_scope(%{user: user}) do
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

  defp use_activation_provider do
    prev = Application.get_env(:flux, Flux.License)
    Application.put_env(:flux, Flux.License, provider: Flux.LicenseActivationTestProvider)

    ExUnit.Callbacks.on_exit(fn ->
      if prev,
        do: Application.put_env(:flux, Flux.License, prev),
        else: Application.delete_env(:flux, Flux.License)

      Application.delete_env(:flux, :test_activation_license)
      # These leak across tests otherwise: they are read by the provider on every
      # mount, so one test's roster silently becomes the next test's fixture.
      Application.delete_env(:flux, :test_node_states)
      Application.delete_env(:flux, :test_node_capacity)
    end)
  end
end
