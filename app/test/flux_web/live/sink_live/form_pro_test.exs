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
