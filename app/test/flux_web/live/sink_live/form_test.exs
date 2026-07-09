defmodule FluxWeb.SinkLive.FormTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flux.SinksFixtures

  setup :register_and_log_in_user

  describe "new sink" do
    test "mounts with new action and shows 'New Sink' title", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sinks/new")

      assert html =~ "New Sink"
    end

    test "shows sink type selector", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sinks/new")

      assert html =~ "HTTP"
      assert html =~ "S3"
      assert html =~ "Postgres"
      assert html =~ "BigQuery"
    end

    test "selecting BigQuery shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "bigquery"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Service Account JSON"
    end

    test "selecting Snowflake shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "snowflake"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Account Identifier"
    end

    test "selecting Redis shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "redis"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Key Template"
    end

    test "selecting MongoDB shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "mongodb"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Collection"
    end

    test "save with valid params creates sink and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      result =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "Test HTTP Sink",
            "config_url" => "https://example.com/webhook",
            "config_method" => "POST"
          }
        })
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/sinks"}}} = result
    end

    test "save with empty name shows validation error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "",
            "config_url" => "https://example.com/webhook"
          }
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can&apos;t be blank" or
               html =~ "can't be blank"
    end
  end

  describe "edit sink" do
    test "mounts with edit action and shows 'Edit Sink' title", %{conn: conn, scope: scope} do
      sink = sink_fixture(scope.organization_id, %{name: "Existing Sink"})

      {:ok, _lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ "Edit Sink"
    end

    test "shows existing sink name in form", %{conn: conn, scope: scope} do
      sink = sink_fixture(scope.organization_id, %{name: "Existing Sink"})

      {:ok, _lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ "Existing Sink"
    end

    test "hydrates non-secret config fields but leaves the secret blank on edit",
         %{conn: conn, scope: scope} do
      sink = postgres_sink_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      # Non-secret fields are pre-filled...
      assert html =~ "orders_stream"
      assert html =~ "event_type"
      # ...but the password-bearing database_url is never rendered.
      refute html =~ "s3cr3t"
    end

    test "editing without re-entering database_url preserves the stored secret and columns",
         %{conn: conn, scope: scope} do
      sink = postgres_sink_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{"sink" => %{"config_table" => "orders_v2"}})
      |> render_submit()

      updated = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert updated.config["table"] == "orders_v2"
      assert updated.config["database_url"] == "postgres://flux:s3cr3t@db.internal:5432/prod"
      assert updated.config["columns"] == %{"event_type" => "type"}
    end

    test "re-entering database_url updates the stored secret", %{conn: conn, scope: scope} do
      sink = postgres_sink_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{
        "sink" => %{"config_database_url" => "postgres://flux:rotated@db.internal:5432/prod"}
      })
      |> render_submit()

      updated = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert updated.config["database_url"] == "postgres://flux:rotated@db.internal:5432/prod"
    end

    test "editing a MySQL sink preserves database_url, columns and the ssl flag left blank",
         %{conn: conn, scope: scope} do
      sink =
        mysql_sink_fixture(scope.organization_id, %{
          config: %{
            "database_url" => "mysql://root:s3cr3t@db.internal:3306/prod",
            "table" => "orders_stream",
            "columns" => %{"event_type" => "type"},
            "ssl" => true
          }
        })

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{"sink" => %{"config_table" => "orders_v2"}})
      |> render_submit()

      updated = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert updated.config["table"] == "orders_v2"
      assert updated.config["database_url"] == "mysql://root:s3cr3t@db.internal:3306/prod"
      assert updated.config["columns"] == %{"event_type" => "type"}
      assert updated.config["ssl"] == true
    end
  end

  defp postgres_sink_fixture(scope) do
    sink_fixture(scope.organization_id, %{
      name: "pg-#{System.unique_integer([:positive])}",
      type: "postgres",
      config: %{
        "mode" => "external",
        "table" => "orders_stream",
        "database_url" => "postgres://flux:s3cr3t@db.internal:5432/prod",
        "columns" => %{"event_type" => "type"}
      }
    })
  end
end
