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

    test "selecting Parquet shows its config fields (Community, no upgrade prompt)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "parquet"})

      refute html =~ "Flux Pro"
      assert html =~ "Partition Template"
      assert html =~ "Explicit Schema"
    end

    test "creates a Parquet sink", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "parquet"})

      result =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "Lake",
            "config_directory" => "events",
            "config_partition_template" => "year={yyyy}/",
            "config_compression" => "zstd",
            "config_compression_level" => "5",
            "config_max_rows" => "5000",
            "config_schema" => ~s({"id": "integer"}),
            "config_schema_mode" => "strict"
          }
        })
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/sinks"}}} = result

      sink = scope.organization_id |> Flux.Sinks.list_sinks() |> Enum.find(&(&1.name == "Lake"))
      assert sink.type == "parquet"

      assert %{
               "directory" => "events",
               "partition_template" => "year={yyyy}/",
               "compression" => "zstd",
               "compression_level" => 5,
               "max_rows" => 5000,
               "schema" => %{"id" => "integer"},
               "schema_mode" => "strict"
             } = sink.config
    end

    test "rejects an unsafe Parquet directory and invalid schema JSON", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "parquet"})

      html =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "Bad Lake",
            "config_directory" => "../escape",
            "config_schema" => "{not json"
          }
        })
        |> render_submit()

      assert html =~ "directory must not contain"
      assert html =~ "schema must be a non-empty JSON object"
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

      # The failure is also surfaced as an error toast, not just an inline error.
      assert html =~ "Couldn&#39;t save sink" or html =~ "Couldn't save sink"
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

    test "editing a Parquet sink hydrates its fields and can clear the schema",
         %{conn: conn, scope: scope} do
      sink =
        sink_fixture(scope.organization_id, %{
          type: "parquet",
          config: %{
            "directory" => "lake",
            "partition_template" => "region={region}/",
            "schema" => %{"id" => "integer"}
          }
        })

      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")
      assert html =~ "region={region}/"
      assert html =~ "&quot;id&quot;:&quot;integer&quot;"

      lv
      |> form("form", %{"sink" => %{"config_schema" => "", "config_partition_template" => ""}})
      |> render_submit()

      updated = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert updated.config["directory"] == "lake"
      assert updated.config["schema"] == nil
      assert updated.config["partition_template"] == ""
    end
  end

  describe "edit Parquet sink" do
    test "clearing the path template restores the default", %{conn: conn, scope: scope} do
      sink =
        sink_fixture(scope.organization_id, %{
          type: "parquet",
          config: %{"directory" => "lake", "path_template" => "custom/{uid}.parquet"}
        })

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{"sink" => %{"config_path_template" => ""}})
      |> render_submit()

      updated = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert updated.config["path_template"] == nil

      assert Flux.Sink.Adapters.Parquet.Settings.from_config(updated.config).path_template ==
               Flux.Sink.Adapters.Parquet.Settings.default_path_template()
    end
  end

  describe "email sink" do
    test "is a Community type: selecting it shows its config, not an upgrade prompt",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "email"})

      refute html =~ "Flux Pro"
      assert html =~ "SMTP Host"
      assert html =~ "From Address"
      assert html =~ "Subject"
    end

    test "switching provider swaps the credential fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "email"})

      html =
        lv
        |> form("form", %{"sink" => %{"config_provider" => "sendgrid"}})
        |> render_change()

      assert html =~ "API Key"
      refute html =~ "SMTP Host"
    end

    test "creates an SMTP email sink with normalized recipients", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "email"})

      result =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "Order alerts",
            "config_provider" => "smtp",
            "config_host" => "smtp.example.com",
            "config_port" => "587",
            "config_security" => "starttls",
            "config_username" => "mailer",
            "config_password" => "smtp-s3cr3t",
            "config_from" => "alerts@example.com",
            "config_to" => "ops@EXAMPLE.com,\noncall@example.com",
            "config_subject" => "Order {order.id} failed",
            "config_max_per_minute" => "10"
          }
        })
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/sinks"}}} = result

      [sink] = Flux.Sinks.list_sinks(scope.organization_id) |> Enum.filter(&(&1.type == "email"))
      assert sink.config["to"] == ["ops@example.com", "oncall@example.com"]
      assert sink.config["password"] == "smtp-s3cr3t"
      assert sink.config["tls_verify"] == true
      assert sink.config["rate_limit"] == %{"max_per_minute" => 10}
    end

    test "shows each invalid recipient as the user types", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "email"})

      html =
        lv
        |> form("form", %{"sink" => %{"config_to" => "ok@example.com, bob@@example.com"}})
        |> render_change()

      assert html =~ "bob@@example.com"
      assert html =~ "exactly one @"
    end

    test "refuses to save an invalid sender", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "email"})

      html =
        lv
        |> form("form", %{
          "sink" => %{
            "name" => "Bad sender",
            "config_host" => "smtp.example.com",
            "config_from" => "alerts@localhost",
            "config_to" => "ops@example.com",
            "config_subject" => "hi"
          }
        })
        |> render_submit()

      assert html =~ "Couldn&#39;t save sink" or html =~ "Couldn't save sink"
      assert html =~ "at least two labels"
    end

    test "editing without re-entering the password keeps it and hydrates recipients",
         %{conn: conn, scope: scope} do
      sink =
        email_sink_fixture(scope.organization_id, %{
          config: %{
            "provider" => "smtp",
            "host" => "smtp.example.com",
            "username" => "mailer",
            "password" => "smtp-s3cr3t",
            "from" => "alerts@example.com",
            "to" => ["ops@example.com", "oncall@example.com"],
            "subject" => "hi"
          }
        })

      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ "ops@example.com, oncall@example.com"
      refute html =~ "smtp-s3cr3t"

      lv
      |> form("form", %{"sink" => %{"config_subject" => "Updated {id}"}})
      |> render_submit()

      updated = Flux.Sinks.get_sink(sink.id, scope.organization_id)
      assert updated.config["subject"] == "Updated {id}"
      assert updated.config["password"] == "smtp-s3cr3t"
      assert updated.config["to"] == ["ops@example.com", "oncall@example.com"]
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
