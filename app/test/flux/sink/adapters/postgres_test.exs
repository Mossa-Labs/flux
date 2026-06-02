defmodule Flux.Sink.Adapters.PostgresTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.Postgres

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
end
