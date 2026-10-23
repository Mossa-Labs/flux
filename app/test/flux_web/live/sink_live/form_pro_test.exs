defmodule FluxWeb.SinkLive.FormProTest do
  # async: false — exercises the Pro-licensed render path by swapping the global
  # license provider via Flux.LicenseHelpers (see DLQLive.IndexTest for the pattern).
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Flux.LicenseHelpers
  import Flux.SinksFixtures

  setup :register_and_log_in_user

  setup do
    state = put_license_tier(:pro)
    on_exit(fn -> reset_license(state) end)
    :ok
  end

  describe "Pro-gated sink types under a licensed tier" do
    test "selecting BigQuery renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "bigquery"})

      assert html =~ "Project ID"
      assert html =~ "Service Account JSON"
      refute html =~ "is a Flux Pro feature"
    end

    test "selecting Snowflake renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "snowflake"})

      assert html =~ "Account Identifier"
      assert html =~ "Warehouse"
      assert html =~ "Private Key (PEM)"
      refute html =~ "is a Flux Pro feature"
    end

    test "selecting Redis renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "redis"})

      assert html =~ "Value Shape"
      assert html =~ "Key Template"
      refute html =~ "is a Flux Pro feature"
    end

    test "selecting MongoDB renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "mongodb"})

      assert html =~ "Collection"
      assert html =~ "Write Mode"
      refute html =~ "is a Flux Pro feature"
    end

    test "selecting Slack renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "slack"})

      assert html =~ "Auth Mode"
      assert html =~ "Webhook URL"
      assert html =~ "Block Kit"
      refute html =~ "is a Flux Pro feature"
    end

    test "selecting DynamoDB renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "dynamodb"})

      assert html =~ "Table Name"
      assert html =~ "Partition Key"
      assert html =~ "Write Mode"
      refute html =~ "are part of Flux Pro"
    end

    test "DynamoDB reveals credential fields for the chosen auth mode", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      html = render_click(lv, "select_type", %{"type" => "dynamodb"})

      # IAM role (the default) needs no credential inputs.
      refute html =~ "Secret Access Key"
      refute html =~ "Role ARN"

      html =
        lv
        |> form("form", %{"sink" => %{"config_auth_mode" => "static"}})
        |> render_change()

      assert html =~ ~s{Access Key ID<span class="text-error}
      assert html =~ ~s{Secret Access Key<span class="text-error}
      assert html =~ "Session Token (optional)"
      refute html =~ "Role ARN"

      html =
        lv
        |> form("form", %{"sink" => %{"config_auth_mode" => "assume_role"}})
        |> render_change()

      assert html =~ ~s{Role ARN<span class="text-error}
      refute html =~ "Secret Access Key"
    end

    test "DynamoDB asks for a version attribute only in if_newer mode", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      html = render_click(lv, "select_type", %{"type" => "dynamodb"})

      refute html =~ "Version Attribute"

      html =
        lv
        |> form("form", %{"sink" => %{"config_write_mode" => "if_newer"}})
        |> render_change()

      assert html =~ ~s{Version Attribute<span class="text-error}
    end

    test "selecting GCS renders the config fields instead of the upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "gcs"})

      assert html =~ ~s(Bucket Name<span class="text-error)
      assert html =~ "Object Name Template"
      assert html =~ "Service Account JSON"
      assert html =~ "Flush After MB"
      refute html =~ "are part of Flux Pro"
    end

    test "GCS compression choices follow the selected format", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "gcs"})
      assert html =~ "Gzip (default)"
      refute html =~ "Snappy"

      html =
        lv
        |> form("form", %{"sink" => %{"config_format" => "parquet"}})
        |> render_change()

      assert html =~ "Snappy (default)"
      assert html =~ "Zstandard"
    end

    test "editing a GCS sink pre-fills settings, shows bytes as MB and never echoes credentials",
         %{conn: conn, scope: scope} do
      # Inserted directly: the Community stub (still registered in core tests)
      # would reject a GCS config at validation.
      sink =
        Flux.Repo.insert!(%Flux.Sinks.Sink{
          name: "lake",
          type: "gcs",
          organization_id: scope.organization_id,
          config: %{
            "bucket" => "lake-bucket",
            "format" => "parquet",
            "compression" => "zstd",
            "max_bytes" => 50 * 1024 * 1024,
            "credentials" => ~s({"private_key":"super-secret"})
          }
        })

      {:ok, _lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ ~s(value="lake-bucket")
      assert html =~ ~s(value="50")
      refute html =~ "super-secret"
    end
  end

  describe "Enterprise-gated sink types" do
    test "stay locked under a Pro license", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      assert has_element?(lv, "#sink-types-pro", "included in your license")
      assert has_element?(lv, "#sink-types-enterprise", "requires a Flux Enterprise license")
      # Pro is fully licensed, so the pricing link moves to the Enterprise group.
      assert has_element?(lv, "#sink-types-enterprise #sink-compare-plans")
      refute has_element?(lv, "#sink-type-s3", "Requires Flux Pro")

      html = render_click(lv, "select_type", %{"type" => "pagerduty"})

      assert has_element?(lv, "#sink-pro-required", "PagerDuty sinks are part of Flux Enterprise")
      refute html =~ "Integration Key"
    end

    test "selecting PagerDuty under an Enterprise license renders its config fields",
         %{conn: conn} do
      put_license_tier(:enterprise)
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      refute has_element?(lv, "#sink-compare-plans")
      assert has_element?(lv, "#sink-types-enterprise", "included in your license")

      html = render_click(lv, "select_type", %{"type" => "pagerduty"})

      assert html =~ "Integration Key"
      assert html =~ "Event Action"
      assert html =~ "Dedup Key Template"
      assert html =~ "Severity Mapping"
      assert html =~ "Custom Details"
      refute has_element?(lv, "#sink-pro-required")
      assert has_element?(lv, "#sink-destination", "Destination · Flux Enterprise")
    end

    test "the dedup key is required once an event can acknowledge or resolve", %{conn: conn} do
      put_license_tier(:enterprise)
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      html = render_click(lv, "select_type", %{"type" => "pagerduty"})

      assert html =~ ~s(Integration Key<span class="text-error)
      refute html =~ ~s(Dedup Key Template<span class="text-error)

      html =
        lv
        |> form("form", %{"sink" => %{"config_event_action" => "resolve"}})
        |> render_change()

      assert html =~ ~s(Dedup Key Template<span class="text-error)

      html =
        lv
        |> form("form", %{
          "sink" => %{"config_event_action" => "trigger", "config_action_field" => "status"}
        })
        |> render_change()

      assert html =~ ~s(Dedup Key Template<span class="text-error)
    end
  end

  describe "editing a PagerDuty sink" do
    # The public build backs "pagerduty" with the Enterprise stub, which rejects
    # every save; a permissive adapter stands in for the licensed one.
    setup do
      put_license_tier(:enterprise)
      Flux.Sink.Registry.register("pagerduty", Flux.Test.PermissiveSinkAdapter)
      on_exit(fn -> Flux.Sink.Registry.register("pagerduty", Flux.Sink.Adapters.Stub) end)
      :ok
    end

    test "never pre-fills the integration key; a blank key keeps the stored one",
         %{conn: conn, scope: scope} do
      sink =
        sink_fixture(scope.organization_id, %{
          type: "pagerduty",
          config: %{
            "routing_key" => "R0STOREDKEY0000000000000000000000",
            "event_action" => "trigger",
            "dedup_key_template" => "{pipeline_id}-{anomaly_type}",
            "severity_field" => "level"
          }
        })

      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      refute html =~ "R0STOREDKEY"
      assert html =~ "{pipeline_id}-{anomaly_type}"

      lv
      |> form("form", %{"sink" => %{"config_routing_key" => "", "config_severity_field" => ""}})
      |> render_submit()

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config
      assert config["routing_key"] == "R0STOREDKEY0000000000000000000000"
      # Optional settings are clearable.
      refute Map.has_key?(config, "severity_field")
      assert config["dedup_key_template"] == "{pipeline_id}-{anomaly_type}"
    end
  end

  describe "required-field markers" do
    test "always-required fields carry a * and optional fields do not", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      html = render_click(lv, "select_type", %{"type" => "mongodb"})

      # Collection is always required; Auth Source is optional.
      assert html =~ ~s(Collection<span class="text-error)
      refute html =~ ~s(Auth Source<span class="text-error)
    end

    test "conditional fields gain a * only when the mode selects them", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      html = render_click(lv, "select_type", %{"type" => "mongodb"})

      # Default auth_mode is "none" — Password is not yet required.
      refute html =~ ~s{Password (SCRAM)<span class="text-error}

      # Switching Auth Mode to SCRAM makes Username/Password required.
      html =
        lv
        |> form("form", %{"sink" => %{"config_auth_mode" => "scram"}})
        |> render_change()

      assert html =~ ~s{Password (SCRAM)<span class="text-error}
      assert html =~ ~s{Username (SCRAM)<span class="text-error}
    end
  end

  describe "editing a GCS sink" do
    # The public build backs "gcs" with the Pro stub, which rejects every save;
    # a permissive adapter stands in for the licensed one.
    setup do
      Flux.Sink.Registry.register("gcs", Flux.Test.PermissiveSinkAdapter)
      on_exit(fn -> Flux.Sink.Registry.register("gcs", Flux.Sink.Adapters.Stub) end)
      :ok
    end

    defp gcs_sink(org_id, config) do
      sink_fixture(org_id, %{
        type: "gcs",
        config: Map.merge(%{"bucket" => "lake-bucket", "format" => "ndjson"}, config)
      })
    end

    defp submit_gcs(lv, params), do: lv |> form("form", %{"sink" => params}) |> render_submit()

    test "an unrelated edit keeps an exact byte threshold the MB field can't show",
         %{conn: conn, scope: scope} do
      sink = gcs_sink(scope.organization_id, %{"max_bytes" => 500_000})
      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      # Shown rounded up to the smallest whole MB.
      assert html =~ ~s(value="1")

      submit_gcs(lv, %{"name" => "renamed"})

      sink = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert sink.name == "renamed"
      assert sink.config["max_bytes"] == 500_000
    end

    test "changing the MB value saves the new threshold", %{conn: conn, scope: scope} do
      sink = gcs_sink(scope.organization_id, %{"max_bytes" => 500_000})
      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      submit_gcs(lv, %{"config_max_mb" => "2"})

      assert Flux.Sinks.get_sink(sink.id, scope.organization_id).config["max_bytes"] ==
               2 * 1024 * 1024
    end
  end

  describe "editing a DynamoDB sink" do
    # The public build backs "dynamodb" with the Pro stub, which rejects every
    # save; a permissive adapter stands in for the licensed one.
    setup do
      Flux.Sink.Registry.register("dynamodb", Flux.Test.PermissiveSinkAdapter)
      on_exit(fn -> Flux.Sink.Registry.register("dynamodb", Flux.Sink.Adapters.Stub) end)
      :ok
    end

    defp dynamodb_sink(org_id, config) do
      sink_fixture(org_id, %{
        type: "dynamodb",
        config:
          Map.merge(
            %{
              "table_name" => "events",
              "partition_key" => "pk",
              "auth_mode" => "static",
              "access_key_id" => "AKIAOLD",
              "secret_access_key" => "old-secret",
              "session_token" => "old-token"
            },
            config
          )
      })
    end

    defp submit(lv, params), do: lv |> form("form", %{"sink" => params}) |> render_submit()

    defp stored_config(sink, scope),
      do: Flux.Sinks.get_sink(sink.id, scope.organization_id).config

    test "clearing optional settings removes them; blank secrets are kept",
         %{conn: conn, scope: scope} do
      sink =
        dynamodb_sink(scope.organization_id, %{
          "sort_key" => "sk",
          "region" => "eu-west-1",
          "endpoint" => "http://localhost:4566",
          "ttl_attribute" => "expires_at",
          "ttl_seconds" => 3600
        })

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      submit(lv, %{
        "config_sort_key" => "",
        "config_region" => "",
        "config_endpoint" => "",
        "config_ttl_attribute" => "",
        "config_ttl_seconds" => ""
      })

      config = stored_config(sink, scope)

      for key <- ~w(sort_key region endpoint ttl_attribute ttl_seconds) do
        refute Map.has_key?(config, key), "expected #{key} to be cleared, got #{inspect(config)}"
      end

      assert config["access_key_id"] == "AKIAOLD"
      assert config["secret_access_key"] == "old-secret"
      assert config["session_token"] == "old-token"
    end

    test "switching away from static auth drops the stored keys and secrets",
         %{conn: conn, scope: scope} do
      sink = dynamodb_sink(scope.organization_id, %{})
      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      submit(lv, %{"config_auth_mode" => "iam_role"})

      config = stored_config(sink, scope)
      assert config["auth_mode"] == "iam_role"

      for key <- ~w(access_key_id secret_access_key session_token) do
        refute Map.has_key?(config, key), "expected #{key} to be dropped, got #{inspect(config)}"
      end
    end

    test "a new secret without a new token drops the stored session token",
         %{conn: conn, scope: scope} do
      sink = dynamodb_sink(scope.organization_id, %{})
      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      submit(lv, %{
        "config_access_key_id" => "AKIANEW",
        "config_secret_access_key" => "new-secret"
      })

      config = stored_config(sink, scope)
      assert config["access_key_id"] == "AKIANEW"
      assert config["secret_access_key"] == "new-secret"
      refute Map.has_key?(config, "session_token")
    end

    test "the remove checkbox clears a stored session token, and only shows when one is stored",
         %{conn: conn, scope: scope} do
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/sinks/#{dynamodb_sink(scope.organization_id, %{"session_token" => nil}).id}/edit"
        )

      refute html =~ "Remove the stored session token"

      sink = dynamodb_sink(scope.organization_id, %{})
      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")
      assert html =~ "Remove the stored session token"

      submit(lv, %{"config_clear_session_token" => "true"})

      config = stored_config(sink, scope)
      refute Map.has_key?(config, "session_token")
      assert config["secret_access_key"] == "old-secret"
    end
  end
end
