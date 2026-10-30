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

    test "selecting GCS shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "gcs"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert has_element?(
               lv,
               "#sink-pro-required",
               "Google Cloud Storage sinks are part of Flux Pro"
             )

      refute html =~ "Object Name Template"
    end

    test "selecting Cassandra shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "cassandra"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert has_element?(lv, "#sink-pro-required", "Cassandra sinks are part of Flux Pro")
      refute html =~ "Contact Points"
    end

    test "selecting MongoDB shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "mongodb"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Collection"
    end

    test "selecting DynamoDB shows the Pro upgrade prompt in Community", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "dynamodb"})

      # Community is not entitled, so the config form is replaced by the upgrade prompt.
      assert html =~ "Flux Pro"
      refute html =~ "Partition Key"
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

      assert html =~ "Directory must not contain"
      assert html =~ "Schema must be a non-empty JSON object"
      assert has_element?(lv, "#sink_config_directory.input-error")
      assert has_element?(lv, "#sink_config_schema.textarea-error")
    end

    test "save with valid params creates sink and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "http"})

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
      render_click(lv, "select_type", %{"type" => "http"})

      lv
      |> form("form", %{
        "sink" => %{
          "name" => "",
          "config_url" => "https://example.com/webhook"
        }
      })
      |> render_submit()

      assert has_element?(lv, "#sink_name.input-error")
      # The summary banner names the field and links to it, instead of a toast.
      assert has_element?(lv, "#sink-form-errors a[href='#sink_name']", "Name can")
      refute render(lv) =~ "Couldn"
    end

    test "a config error shows under its own field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "http"})

      lv
      |> form("form", %{"sink" => %{"name" => "Hook", "config_url" => ""}})
      |> render_submit()

      assert has_element?(lv, "#sink_config_url.input-error")
      assert has_element?(lv, "#sink-form-errors a[href='#sink_config_url']", "URL is required")
    end

    test "picking another destination clears the error summary", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "http"})
      lv |> form("form", %{"sink" => %{"name" => ""}}) |> render_submit()
      assert has_element?(lv, "#sink-form-errors")

      render_click(lv, "change_type", %{})
      render_click(lv, "select_type", %{"type" => "postgres"})

      refute has_element?(lv, "#sink-form-errors")
    end
  end

  describe "destination picker" do
    test "starts with no destination chosen and submit disabled", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      refute has_element?(lv, "#sink-destination button[aria-pressed='true']")
      refute has_element?(lv, "#sink-connection")
      assert has_element?(lv, "#sink-submit[disabled]")
      assert has_element?(lv, "#sink-submit-hint", "Choose a destination to continue")
    end

    test "groups Community and Pro destinations and marks the locked ones", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      assert has_element?(lv, "#sink-types-community + div #sink-type-http")
      assert has_element?(lv, "#sink-types-pro + div #sink-type-s3")
      # Community isn't entitled to Pro types, so each says so before it's clicked.
      assert has_element?(lv, "#sink-type-s3", "Requires Flux Pro")
      refute has_element?(lv, "#sink-type-http", "Requires Flux Pro")
    end

    test "every tile puts its sublabel on the row under its name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      # Community tiles have no lock column; without an explicit row the
      # sublabel would auto-place beside the name instead of under it.
      for type <- ~w(http s3) do
        assert has_element?(lv, "#sink-type-#{type} span.row-start-2")
      end
    end

    test "choosing a type collapses the picker to a summary that can be reopened",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      render_click(lv, "select_type", %{"type" => "postgres"})

      refute has_element?(lv, "#sink-type-http")
      assert has_element?(lv, "#sink-destination", "Postgres")
      assert has_element?(lv, "#sink-connection")
      refute has_element?(lv, "#sink-submit[disabled]")

      lv |> element("#sink-type-change") |> render_click()

      assert has_element?(lv, "#sink-type-postgres[aria-pressed='true']")
    end

    test "focus follows the destination so keyboard users keep their place", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      # The focused tile disappears, so focus moves to the first setting...
      render_click(lv, "select_type", %{"type" => "postgres"})
      assert_push_event(lv, "sink-form:focus", %{to: "#sink-connection " <> _})

      # ...and back to the chosen tile when the picker reopens.
      lv |> element("#sink-type-change") |> render_click()
      assert_push_event(lv, "sink-form:focus", %{to: "#sink-type-postgres"})
      assert has_element?(lv, "#sink-type-postgres")

      # A locked type has no settings; focus lands on the upgrade heading.
      render_click(lv, "select_type", %{"type" => "s3"})
      assert_push_event(lv, "sink-form:focus", %{to: "#sink-pro-required-title"})
      assert has_element?(lv, "#sink-pro-required-title[tabindex='-1']")
    end

    test "a locked Pro type disables submit and explains why", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      render_click(lv, "select_type", %{"type" => "s3"})

      assert has_element?(lv, "#sink-pro-required", "S3 sinks are part of Flux Pro")
      assert has_element?(lv, "#sink-submit[disabled]")
      assert has_element?(lv, "#sink-submit-hint", "S3 sinks need Flux Pro")
      refute has_element?(lv, "#sink-details")
    end

    test "lists Enterprise destinations in their own locked group", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/sinks/new")

      assert has_element?(lv, "#sink-types-enterprise + div #sink-type-pagerduty")
      refute has_element?(lv, "#sink-types-pro + div #sink-type-pagerduty")
      assert has_element?(lv, "#sink-types-enterprise", "requires a Flux Enterprise license")
      assert has_element?(lv, "#sink-type-pagerduty", "Requires Flux Enterprise")
      # One pricing link, however many editions are locked.
      assert [_] = Regex.scan(~r/id="sink-compare-plans"/, html)
      assert has_element?(lv, "#sink-types-pro #sink-compare-plans")
    end

    test "a locked Enterprise type names Flux Enterprise, not Pro", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      html = render_click(lv, "select_type", %{"type" => "pagerduty"})

      assert has_element?(lv, "#sink-pro-required", "PagerDuty sinks are part of Flux Enterprise")
      assert has_element?(lv, "#sink-submit-hint", "PagerDuty sinks need Flux Enterprise")
      assert has_element?(lv, "#sink-destination", "Destination · Flux Enterprise")
      refute html =~ "Integration Key"
    end

    test "pricing links open in a new tab so the form isn't lost", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")

      assert has_element?(lv, "#sink-compare-plans[target='_blank'][rel~='noopener']")

      render_click(lv, "select_type", %{"type" => "s3"})

      assert has_element?(lv, "#sink-view-pricing[target='_blank'][rel~='noopener']")
    end

    test "Postgres asks for a database URL only in external mode", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "postgres"})

      refute has_element?(lv, "#sink_config_database_url")

      lv |> form("form", %{"sink" => %{"config_mode" => "external"}}) |> render_change()

      assert has_element?(lv, "#sink_config_database_url")
    end

    test "description stays behind a link until asked for", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "http"})

      refute has_element?(lv, "#sink_description")

      lv |> element("#sink-add-description") |> render_click()

      assert has_element?(lv, "#sink_description")
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

    test "opens with the type collapsed and an existing description shown",
         %{conn: conn, scope: scope} do
      sink = sink_fixture(scope.organization_id, %{description: "Order webhooks"})

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      refute has_element?(lv, "#sink-type-postgres")
      assert has_element?(lv, "#sink-destination", "HTTP")
      assert has_element?(lv, "#sink_description", "Order webhooks")
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

      assert has_element?(lv, "#sink-form-errors a[href='#sink_config_from']")
      assert has_element?(lv, "#sink_config_from.input-error")
      assert html =~ "at least two labels"
    end

    test "clearing saved bodies and optional fields removes them", %{conn: conn, scope: scope} do
      sink =
        email_sink_fixture(scope.organization_id, %{
          config: %{
            "provider" => "smtp",
            "host" => "smtp.example.com",
            "port" => 2525,
            "username" => "mailer",
            "password" => "smtp-s3cr3t",
            "from" => "alerts@example.com",
            "from_name" => "Alerts",
            "reply_to" => "help@example.com",
            "to" => ["ops@example.com"],
            "subject" => "hi",
            "html_body" => "<p>old html</p>",
            "text_body" => "old text",
            "rate_limit" => %{"max_per_minute" => 5}
          }
        })

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{
        "sink" => %{
          "config_html_body" => "",
          "config_text_body" => "",
          "config_reply_to" => "",
          "config_from_name" => "",
          "config_port" => "",
          "config_max_per_minute" => ""
        }
      })
      |> render_submit()

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config

      for key <- ~w(html_body text_body reply_to from_name port rate_limit) do
        refute Map.has_key?(config, key), "expected #{key} to be cleared, got #{inspect(config)}"
      end

      # The secret, left blank, is still kept.
      assert config["password"] == "smtp-s3cr3t"
      assert config["subject"] == "hi"
    end

    test "clearing a required field is a validation error, not a silent revert",
         %{conn: conn, scope: scope} do
      sink = email_sink_fixture(scope.organization_id)

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      html =
        lv
        |> form("form", %{"sink" => %{"config_subject" => ""}})
        |> render_submit()

      assert html =~ "Subject is required"
      assert has_element?(lv, "#sink-form-errors a[href='#sink_config_subject']")

      assert Flux.Sinks.get_sink(sink.id, scope.organization_id).config["subject"] ==
               sink.config["subject"]
    end

    test "recipients saved as a comma-separated string survive editing",
         %{conn: conn, scope: scope} do
      sink =
        email_sink_fixture(scope.organization_id, %{
          config: %{
            "provider" => "smtp",
            "host" => "smtp.example.com",
            "from" => "alerts@example.com",
            "to" => "ops@example.com, oncall@example.com",
            "cc" => "lead@example.com",
            "subject" => "hi"
          }
        })

      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      assert html =~ "ops@example.com, oncall@example.com"
      assert html =~ "lead@example.com"

      result =
        lv
        |> form("form", %{"sink" => %{"config_subject" => "updated"}})
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/sinks"}}} = result

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config
      assert config["to"] == ["ops@example.com", "oncall@example.com"]
      assert config["cc"] == ["lead@example.com"]
    end

    test "switching provider with a blank key is rejected instead of reusing the old key",
         %{conn: conn, scope: scope} do
      sink = sendgrid_sink_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      html =
        lv
        |> form("form", %{"sink" => %{"config_provider" => "postmark"}})
        |> render_submit()

      assert html =~ "API key is required"
      assert has_element?(lv, "#sink_config_api_key.input-error")

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config
      assert config["provider"] == "sendgrid"
      assert config["api_key"] == "SG.old-sendgrid-key"
    end

    test "the port hint shows the default for the chosen encryption", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "email"})

      assert has_element?(lv, "#sink_config_port[placeholder='Default: 587']")

      lv |> form("form", %{"sink" => %{"config_security" => "ssl"}}) |> render_change()

      assert has_element?(lv, "#sink_config_port[placeholder='Default: 465']")
    end

    test "the error summary follows the form's field order", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sinks/new")
      render_click(lv, "select_type", %{"type" => "email"})
      lv |> form("form", %{"sink" => %{"config_provider" => "sendgrid"}}) |> render_change()

      lv
      |> form("form", %{"sink" => %{"name" => "", "config_provider" => "sendgrid"}})
      |> render_submit()

      banner = lv |> element("#sink-form-errors") |> render()

      # API Key comes first on the page (under Send With), then the sender,
      # recipients and message, then Details. The adapter reports them in a
      # different order.
      positions =
        Enum.map(["API key", "From address", "To must", "Subject", "Name can"], fn text ->
          {index, _} = :binary.match(banner, text)
          index
        end)

      assert positions == Enum.sort(positions)
    end

    test "switching provider saves the new provider's key", %{conn: conn, scope: scope} do
      sink = sendgrid_sink_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      result =
        lv
        |> form("form", %{
          "sink" => %{"config_provider" => "postmark", "config_api_key" => "pm-new-token"}
        })
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/sinks"}}} = result

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config
      assert config["provider"] == "postmark"
      assert config["api_key"] == "pm-new-token"
    end

    test "switching away drops the old provider's secrets", %{conn: conn, scope: scope} do
      sink = email_sink_fixture(scope.organization_id)
      assert sink.config["password"] == "smtp-s3cr3t"

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{"sink" => %{"config_provider" => "system"}})
      |> render_submit()

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config
      assert config["provider"] == "system"
      refute Map.has_key?(config, "password")
    end

    test "keeping the provider keeps a blank API key", %{conn: conn, scope: scope} do
      sink = sendgrid_sink_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/sinks/#{sink.id}/edit")

      lv
      |> form("form", %{"sink" => %{"config_subject" => "updated"}})
      |> render_submit()

      config = Flux.Sinks.get_sink(sink.id, scope.organization_id).config
      assert config["subject"] == "updated"
      assert config["api_key"] == "SG.old-sendgrid-key"
    end

    test "the key field asks for a new key once the provider changes",
         %{conn: conn, scope: scope} do
      sink = sendgrid_sink_fixture(scope)

      {:ok, lv, html} = live(conn, ~p"/sinks/#{sink.id}/edit")
      assert html =~ "Leave blank to keep current"
      # `required` renders the label's `*` marker (span[title=required]).
      refute has_element?(lv, ~s(#email-api-fields span[title="required"]))

      html =
        lv
        |> form("form", %{"sink" => %{"config_provider" => "postmark"}})
        |> render_change()

      refute html =~ "Leave blank to keep current"
      assert has_element?(lv, ~s(#email-api-fields span[title="required"]))
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

  defp sendgrid_sink_fixture(scope) do
    email_sink_fixture(scope.organization_id, %{
      config: %{
        "provider" => "sendgrid",
        "api_key" => "SG.old-sendgrid-key",
        "from" => "alerts@example.com",
        "to" => ["ops@example.com"],
        "subject" => "hi"
      }
    })
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
