defmodule FluxWeb.SinkLive.FormProTest do
  # async: false — exercises the Pro-licensed render path by swapping the global
  # license provider via Flux.LicenseHelpers (see DLQLive.IndexTest for the pattern).
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Flux.LicenseHelpers

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
end
