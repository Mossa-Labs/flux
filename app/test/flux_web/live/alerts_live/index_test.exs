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
               Flux.AlertsTestProvider.stored_rules(org_id)
    end

    @slack_url "https://hooks.slack.com/services/T000/B000/XXXXXXXXXXXXXXXX"
    @webhook_url "https://example.com/hooks/flux?token=s3cr3t-token"

    defp create_url_rule(conn) do
      {:ok, lv, _html} = live(conn, ~p"/system/alerts")
      lv |> element("button", "New rule") |> render_click()

      lv
      |> form("#alert-rule-form", %{
        "rule" => %{
          "name" => "Failures to chat",
          "trigger_type" => "failure_rate",
          "slack_url" => @slack_url,
          "webhook_url" => @webhook_url
        }
      })
      |> render_submit()

      lv
    end

    defp stored_config(org_id, type) do
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)
      Enum.find_value(rule.channels, &(&1["type"] == type && &1["config"]))
    end

    test "editing never echoes Slack or webhook URLs; blank fields keep them",
         %{conn: conn, org_id: org_id} do
      lv = create_url_rule(conn)
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)

      html = render(lv)
      refute html =~ "XXXXXXXXXXXXXXXX"
      refute html =~ "s3cr3t-token"

      html = lv |> element("#alert-rule-#{rule.id} button", "Edit") |> render_click()

      refute html =~ "XXXXXXXXXXXXXXXX"
      refute html =~ "s3cr3t-token"
      refute html =~ "[REDACTED]"
      assert html =~ "Stored — leave blank to keep it"
      assert has_element?(lv, ~s(input[name="rule[slack_url]"][type="password"]))
      assert has_element?(lv, ~s(input[name="rule[webhook_url]"][type="password"]))

      lv
      |> form("#alert-rule-form", %{
        "rule" => %{"name" => "Renamed", "slack_url" => "", "webhook_url" => ""}
      })
      |> render_submit()

      assert stored_config(org_id, "slack") == %{"url" => @slack_url}
      assert stored_config(org_id, "webhook") == %{"url" => @webhook_url}
    end

    test "a new URL replaces the stored one", %{conn: conn, org_id: org_id} do
      lv = create_url_rule(conn)
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)

      lv |> element("#alert-rule-#{rule.id} button", "Edit") |> render_click()

      lv
      |> form("#alert-rule-form", %{"rule" => %{"slack_url" => "https://hooks.slack.com/new"}})
      |> render_submit()

      assert stored_config(org_id, "slack") == %{"url" => "https://hooks.slack.com/new"}
      assert stored_config(org_id, "webhook") == %{"url" => @webhook_url}
    end

    test "the remove checkboxes drop the Slack and webhook channels",
         %{conn: conn, org_id: org_id} do
      lv = create_url_rule(conn)
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)

      lv |> element("#alert-rule-#{rule.id} button", "Edit") |> render_click()

      lv
      |> form("#alert-rule-form", %{
        "rule" => %{
          "email_to" => "ops@acme.com",
          "slack_remove" => "true",
          "webhook_remove" => "true"
        }
      })
      |> render_submit()

      assert stored_config(org_id, "slack") == nil
      assert stored_config(org_id, "webhook") == nil
      assert stored_config(org_id, "email") == %{"to" => "ops@acme.com"}
    end

    test "Test sends through the provider with the stored secrets", %{conn: conn, org_id: org_id} do
      lv = create_url_rule(conn)
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)

      html = lv |> element("#alert-rule-#{rule.id} button", "Test") |> render_click()

      assert html =~ "Sent a test to 2 channel(s)."

      assert [%{"config" => %{"url" => @webhook_url}}, %{"config" => %{"url" => @slack_url}}] =
               Enum.sort_by(Flux.AlertsTestProvider.tested_channels(), & &1["type"], :desc)
    end

    test "a stored PagerDuty channel survives an edit under a Pro license",
         %{conn: conn, org_id: org_id} do
      pagerduty = %{
        "type" => "pagerduty",
        "config" => %{
          "routing_key" => "R0123456789ABCDEF0123456789ABCDE",
          "severity" => "critical"
        }
      }

      Flux.AlertsTestProvider.reset([
        %{
          id: 1,
          organization_id: org_id,
          name: "On-call",
          trigger_type: :anomaly,
          trigger_config: %{},
          channels: [pagerduty],
          enabled: true,
          cooldown_minutes: 15,
          last_fired_at: nil,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

      {:ok, lv, _html} = live(conn, ~p"/system/alerts")
      lv |> element("#alert-rule-1 button", "Edit") |> render_click()

      lv |> form("#alert-rule-form", %{"rule" => %{"name" => "Renamed"}}) |> render_submit()

      assert stored_config(org_id, "pagerduty") == pagerduty["config"]
    end

    test "the PagerDuty channel stays locked under a Pro license", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/system/alerts")

      html = lv |> element("button", "New rule") |> render_click()

      assert has_element?(lv, "#alert-pagerduty-channel", "PagerDuty integration")
      assert html =~ "requires Flux Enterprise."
      refute html =~ "PagerDuty integration key"
    end
  end

  describe "owner on an Enterprise tier (PagerDuty channel entitled)" do
    setup [:register_and_log_in_user, :make_owner]

    setup do
      state = put_license_tier(:enterprise)
      Flux.AlertsTestProvider.reset()
      Flux.Alerts.Registry.set_active(Flux.AlertsTestProvider)

      on_exit(fn ->
        Flux.Alerts.Registry.set_active(Flux.Alerts.Providers.Community)
        reset_license(state)
      end)

      :ok
    end

    @key "R0123456789ABCDEF0123456789ABCDE"

    defp create_pagerduty_rule(conn) do
      {:ok, lv, _html} = live(conn, ~p"/system/alerts")
      lv |> element("button", "New rule") |> render_click()

      lv
      |> form("#alert-rule-form", %{
        "rule" => %{
          "name" => "Anomaly to on-call",
          "trigger_type" => "anomaly",
          "pagerduty_routing_key" => @key,
          "pagerduty_severity" => "critical"
        }
      })
      |> render_submit()

      lv
    end

    defp pagerduty_channels(org_id) do
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)
      Enum.filter(rule.channels, &(&1["type"] == "pagerduty"))
    end

    test "creates a rule with a PagerDuty channel", %{conn: conn, org_id: org_id} do
      create_pagerduty_rule(conn)

      assert [%{"config" => %{"routing_key" => @key, "severity" => "critical"}}] =
               pagerduty_channels(org_id)
    end

    test "editing never echoes the integration key; a blank key keeps it",
         %{conn: conn, org_id: org_id} do
      lv = create_pagerduty_rule(conn)
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)

      html = lv |> element("#alert-rule-#{rule.id} button", "Edit") |> render_click()

      refute html =~ @key
      assert html =~ "Stored — leave blank to keep it"

      lv
      |> form("#alert-rule-form", %{
        "rule" => %{"pagerduty_routing_key" => "", "pagerduty_severity" => "warning"}
      })
      |> render_submit()

      assert [%{"config" => %{"routing_key" => @key, "severity" => "warning"}}] =
               pagerduty_channels(org_id)
    end

    test "the remove checkbox drops the PagerDuty channel", %{conn: conn, org_id: org_id} do
      lv = create_pagerduty_rule(conn)
      [rule] = Flux.AlertsTestProvider.stored_rules(org_id)

      lv |> element("#alert-rule-#{rule.id} button", "Edit") |> render_click()

      lv
      |> form("#alert-rule-form", %{
        "rule" => %{"email_to" => "ops@acme.com", "pagerduty_remove" => "true"}
      })
      |> render_submit()

      assert pagerduty_channels(org_id) == []
    end
  end
end
