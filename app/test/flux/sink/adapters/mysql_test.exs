defmodule Flux.Sink.Adapters.MySQLTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.MySQL

  @valid %{
    "database_url" => "mysql://user:pass@host:3306/db",
    "table" => "events",
    "columns" => %{"type" => "event_type"}
  }

  describe "validate_config/1" do
    test "valid config returns :ok" do
      assert :ok = MySQL.validate_config(@valid)
    end

    test "valid config with each on_conflict mode returns :ok" do
      for mode <- ["raise", "ignore", "update"] do
        assert :ok = MySQL.validate_config(Map.put(@valid, "on_conflict", mode))
      end
    end

    test "missing table returns error" do
      config = Map.delete(@valid, "table")
      assert {:error, errors} = MySQL.validate_config(config)
      assert "table is required" in errors
    end

    test "missing columns returns error" do
      config = Map.delete(@valid, "columns")
      assert {:error, errors} = MySQL.validate_config(config)
      assert "columns mapping is required" in errors
    end

    test "empty columns returns error" do
      config = Map.put(@valid, "columns", %{})
      assert {:error, errors} = MySQL.validate_config(config)
      assert "columns must be a non-empty map" in errors
    end

    test "missing database_url returns error" do
      config = Map.delete(@valid, "database_url")
      assert {:error, errors} = MySQL.validate_config(config)
      assert "database_url is required" in errors
    end

    test "non-mysql database_url scheme returns error" do
      config = Map.put(@valid, "database_url", "postgres://user:pass@host:5432/db")
      assert {:error, errors} = MySQL.validate_config(config)
      assert Enum.any?(errors, &String.contains?(&1, "mysql:// URL"))
    end

    test "invalid on_conflict returns error" do
      config = Map.put(@valid, "on_conflict", "replace_all")
      assert {:error, errors} = MySQL.validate_config(config)
      assert Enum.any?(errors, &String.contains?(&1, "on_conflict must be"))
    end

    test "missing both table and columns returns multiple errors" do
      assert {:error, errors} = MySQL.validate_config(%{"database_url" => "mysql://h/db"})
      assert "table is required" in errors
      assert "columns mapping is required" in errors
    end
  end

  describe "build_insert_sql/3" do
    test "plain insert with backtick-quoted identifiers and ? placeholders" do
      sql = MySQL.build_insert_sql("events", ["type", "user_id"], "raise")
      assert sql == "INSERT INTO `events` (`type`, `user_id`) VALUES (?, ?)"
    end

    test "ignore uses INSERT IGNORE" do
      sql = MySQL.build_insert_sql("events", ["type"], "ignore")
      assert sql == "INSERT IGNORE INTO `events` (`type`) VALUES (?)"
    end

    test "update appends ON DUPLICATE KEY UPDATE for every column" do
      sql = MySQL.build_insert_sql("events", ["id", "type"], "update")

      assert sql ==
               "INSERT INTO `events` (`id`, `type`) VALUES (?, ?) " <>
                 "ON DUPLICATE KEY UPDATE `id` = VALUES(`id`), `type` = VALUES(`type`)"
    end

    test "escapes embedded backticks in identifiers" do
      sql = MySQL.build_insert_sql("ev`il", ["c`ol"], "raise")
      assert sql == "INSERT INTO `ev``il` (`c``ol`) VALUES (?)"
    end

    test "accepts atom column names" do
      sql = MySQL.build_insert_sql("events", [:type], "raise")
      assert sql == "INSERT INTO `events` (`type`) VALUES (?)"
    end
  end

  describe "coerce_value/1" do
    test "JSON-encodes maps" do
      assert MySQL.coerce_value(%{"a" => 1}) == ~s({"a":1})
    end

    test "JSON-encodes lists" do
      assert MySQL.coerce_value([1, 2, 3]) == "[1,2,3]"
    end

    test "passes scalars through unchanged" do
      assert MySQL.coerce_value("hello") == "hello"
      assert MySQL.coerce_value(42) == 42
      assert MySQL.coerce_value(nil) == nil
    end

    test "passes structs (e.g. DateTime) through to MyXQL encoding" do
      dt = ~U[2026-06-23 12:00:00Z]
      assert MySQL.coerce_value(dt) == dt
    end
  end
end
