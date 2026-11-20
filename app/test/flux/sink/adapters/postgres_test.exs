defmodule Flux.Sink.Adapters.PostgresTest do
  use Flux.DataCase, async: true

  alias Flux.Sink.Adapters.Postgres

  use Flux.SinkConformance,
    adapter: Postgres,
    type: "postgres",
    valid_config: %{"table" => "events", "columns" => %{"type" => "event_type"}},
    invalid_configs: [
      %{},
      %{"table" => "events"},
      %{"mode" => "external", "table" => "events", "columns" => %{"a" => "b"}}
    ],
    # The table does not exist: delivery must come back as {:error, _}, not raise.
    deliver_config: %{"table" => "conformance_missing_table", "columns" => %{"id" => "id"}}

  describe "validate_config/1" do
    test "valid internal config with table and columns returns :ok" do
      config = %{"table" => "events", "columns" => %{"type" => "event_type"}}
      assert :ok = Postgres.validate_config(config)
    end

    test "valid internal config with on_conflict returns :ok" do
      config = %{
        "table" => "events",
        "columns" => %{"type" => "event_type"},
        "on_conflict" => "nothing"
      }

      assert :ok = Postgres.validate_config(config)
    end

    test "valid external config with database_url returns :ok" do
      config = %{
        "mode" => "external",
        "table" => "events",
        "columns" => %{"type" => "event_type"},
        "database_url" => "postgres://user:pass@host:5432/db"
      }

      assert :ok = Postgres.validate_config(config)
    end

    test "missing table returns error" do
      config = %{"columns" => %{"type" => "event_type"}}
      assert {:error, errors} = Postgres.validate_config(config)
      assert "table is required" in errors
    end

    test "missing columns returns error" do
      config = %{"table" => "events"}
      assert {:error, errors} = Postgres.validate_config(config)
      assert "columns mapping is required" in errors
    end

    test "external mode without database_url returns error" do
      config = %{
        "mode" => "external",
        "table" => "events",
        "columns" => %{"type" => "event_type"}
      }

      assert {:error, errors} = Postgres.validate_config(config)
      assert "database_url is required for external mode" in errors
    end

    test "invalid mode returns error" do
      config = %{
        "mode" => "invalid",
        "table" => "events",
        "columns" => %{"type" => "event_type"}
      }

      assert {:error, errors} = Postgres.validate_config(config)
      assert Enum.any?(errors, &String.contains?(&1, "mode must be 'internal' or 'external'"))
    end

    test "invalid on_conflict returns error" do
      config = %{
        "table" => "events",
        "columns" => %{"type" => "event_type"},
        "on_conflict" => "invalid"
      }

      assert {:error, errors} = Postgres.validate_config(config)
      assert Enum.any?(errors, &String.contains?(&1, "on_conflict must be"))
    end

    test "on_conflict replace_all is valid" do
      config = %{
        "table" => "events",
        "columns" => %{"type" => "event_type"},
        "on_conflict" => "replace_all"
      }

      assert :ok = Postgres.validate_config(config)
    end

    test "on_conflict raise is valid" do
      config = %{
        "table" => "events",
        "columns" => %{"type" => "event_type"},
        "on_conflict" => "raise"
      }

      assert :ok = Postgres.validate_config(config)
    end

    test "missing both table and columns returns multiple errors" do
      config = %{}
      assert {:error, errors} = Postgres.validate_config(config)
      assert "table is required" in errors
      assert "columns mapping is required" in errors
    end

    test "defaults to internal mode when mode is not specified" do
      config = %{"table" => "events", "columns" => %{"type" => "event_type"}}
      assert :ok = Postgres.validate_config(config)
    end
  end

  describe "deliver/3 — internal mode can't reach Flux's own tables" do
    # Internal mode writes with the app's own database connection, so the table
    # name a user types must never resolve to one of Flux's tables (members, API
    # keys, users...). It is confined to the sink_data schema.
    setup do
      # Shaped like Flux's own tables (Ecto timestamps), so on an unconfined
      # sink the insert would succeed.
      Flux.Repo.query!("""
      CREATE TABLE public.sink_victim (
        id bigserial PRIMARY KEY,
        role text,
        inserted_at timestamptz,
        updated_at timestamptz
      )
      """)

      :ok
    end

    test "a bare name resolves to the sink_data table, never the public one of the same name" do
      Flux.Repo.query!("""
      CREATE TABLE sink_data.sink_victim (
        id bigserial PRIMARY KEY,
        role text,
        inserted_at timestamptz,
        updated_at timestamptz
      )
      """)

      config = %{"table" => "sink_victim", "columns" => %{"role" => "role"}}

      assert :ok = Postgres.deliver(%{"role" => "owner"}, config, [])
      assert %{rows: [[1]]} = Flux.Repo.query!("SELECT count(*) FROM sink_data.sink_victim")
      assert %{rows: [[0]]} = Flux.Repo.query!("SELECT count(*) FROM public.sink_victim")
    end

    test "a quote in a column name is refused and writes nothing" do
      Flux.Repo.query!(
        "CREATE TABLE sink_data.sink_cols (role text, inserted_at timestamptz, updated_at timestamptz)"
      )

      config = %{"table" => "sink_cols", "columns" => %{"role" => ~s[role" text); --]}}

      assert {:error, _} = Postgres.deliver(%{"role" => "owner"}, config, [])
      assert %{rows: [[0]]} = Flux.Repo.query!("SELECT count(*) FROM sink_data.sink_cols")
    end

    test "validate_config requires a plain table name in internal mode only" do
      for bad <- ["public.events", "events\n", "1events", String.duplicate("a", 64), ~s(a"b)] do
        assert {:error, [msg]} =
                 Postgres.validate_config(%{"table" => bad, "columns" => %{"a" => "a"}})

        assert msg =~ "plain table name"
      end

      assert :ok = Postgres.validate_config(%{"table" => "events_2", "columns" => %{"a" => "a"}})

      assert :ok =
               Postgres.validate_config(%{
                 "mode" => "external",
                 "database_url" => "postgres://u:p@h/db",
                 "table" => "public.events",
                 "columns" => %{"a" => "a"}
               })
    end

    for table <- ["sink_victim", "public.sink_victim", ~s(public"."sink_victim)] do
      test "refuses to write #{inspect(table)} outside the sink_data schema" do
        config = %{"table" => unquote(table), "columns" => %{"role" => "role"}}

        assert {:error, _} = Postgres.deliver(%{"role" => "owner"}, config, [])

        assert %{rows: [[0]]} = Flux.Repo.query!("SELECT count(*) FROM public.sink_victim")
      end
    end
  end

  describe "deliver/3 — internal mode" do
    setup do
      # Created inside the sandbox transaction, so it is rolled back after each
      # test and every test starts clean without a migration.
      Flux.Repo.query!("""
      CREATE TABLE sink_data.sink_events (
        id bigserial PRIMARY KEY,
        event_type text,
        user_id text,
        inserted_at timestamptz,
        updated_at timestamptz,
        UNIQUE (event_type)
      )
      """)

      :ok
    end

    defp count_rows do
      %{rows: [[count]]} = Flux.Repo.query!("SELECT count(*) FROM sink_data.sink_events")
      count
    end

    test "inserts a row, mapping nested dot-path fields into columns" do
      config = %{
        "table" => "sink_events",
        "columns" => %{"type" => "event_type", "payload.user_id" => "user_id"}
      }

      data = %{"type" => "signup", "payload" => %{"user_id" => "u-1"}}

      assert :ok = Postgres.deliver(data, config, [])

      assert %{rows: [["signup", "u-1"]]} =
               Flux.Repo.query!("SELECT event_type, user_id FROM sink_data.sink_events")
    end

    test "maps a missing nested path to NULL" do
      config = %{
        "table" => "sink_events",
        "columns" => %{"type" => "event_type", "payload.user_id" => "user_id"}
      }

      assert :ok = Postgres.deliver(%{"type" => "ping"}, config, [])

      assert %{rows: [["ping", nil]]} =
               Flux.Repo.query!("SELECT event_type, user_id FROM sink_data.sink_events")
    end

    test "auto-populates inserted_at/updated_at timestamps" do
      config = %{"table" => "sink_events", "columns" => %{"type" => "event_type"}}

      assert :ok = Postgres.deliver(%{"type" => "ts"}, config, [])

      assert %{rows: [[inserted, updated]]} =
               Flux.Repo.query!("SELECT inserted_at, updated_at FROM sink_data.sink_events")

      refute is_nil(inserted)
      refute is_nil(updated)
    end

    test "on_conflict \"nothing\" ignores a duplicate and reports it" do
      config = %{
        "table" => "sink_events",
        "columns" => %{"type" => "event_type"},
        "on_conflict" => "nothing"
      }

      assert :ok = Postgres.deliver(%{"type" => "dup"}, config, [])
      assert {:ok, :conflict_ignored} = Postgres.deliver(%{"type" => "dup"}, config, [])
      assert count_rows() == 1
    end

    test "on_conflict \"replace_all\" is rejected on a schemaless internal insert" do
      # Ecto's schemaless `insert_all` cannot express `:replace_all`, so the
      # internal path surfaces a rescued insert error. This documents the
      # current limitation (replace_all upserts require external mode).
      config = %{
        "table" => "sink_events",
        "columns" => %{"type" => "event_type"},
        "on_conflict" => "replace_all",
        "conflict_target" => ["event_type"]
      }

      assert {:error, {:insert_error, msg}} = Postgres.deliver(%{"type" => "x"}, config, [])
      assert msg =~ "replace_all"
    end

    test "default on_conflict \"raise\" surfaces a rescued postgres error on duplicate" do
      config = %{"table" => "sink_events", "columns" => %{"type" => "event_type"}}

      assert :ok = Postgres.deliver(%{"type" => "boom"}, config, [])
      assert {:error, {:postgres_error, _msg}} = Postgres.deliver(%{"type" => "boom"}, config, [])
    end
  end

  describe "test_connection/1" do
    test "internal mode succeeds against the app repo" do
      assert :ok = Postgres.test_connection(%{"mode" => "internal"})
    end

    test "external mode with an unreachable url returns an error" do
      config = %{
        "mode" => "external",
        "database_url" => "postgres://nope:nope@127.0.0.1:1/none"
      }

      assert {:error, _reason} = Postgres.test_connection(config)
    end
  end
end
