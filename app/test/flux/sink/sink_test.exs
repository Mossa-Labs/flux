defmodule Flux.SinkTest do
  use ExUnit.Case, async: true

  alias Flux.Sink

  describe "adapter_for_type/1" do
    test "returns HTTP adapter for \"http\"" do
      assert {:ok, Flux.Sink.Adapters.HTTP} = Sink.adapter_for_type("http")
    end

    test "returns Stub adapter for \"s3\" in Community (real S3 is Pro)" do
      assert {:ok, Flux.Sink.Adapters.Stub} = Sink.adapter_for_type("s3")
    end

    test "returns Stub adapter for \"bigquery\" in Community (real BigQuery is Pro)" do
      assert {:ok, Flux.Sink.Adapters.Stub} = Sink.adapter_for_type("bigquery")
    end

    test "returns Postgres adapter for \"postgres\"" do
      assert {:ok, Flux.Sink.Adapters.Postgres} = Sink.adapter_for_type("postgres")
    end

    test "returns MySQL adapter for \"mysql\"" do
      assert {:ok, Flux.Sink.Adapters.MySQL} = Sink.adapter_for_type("mysql")
    end

    test "returns error for unknown type" do
      assert {:error, :unknown_type} = Sink.adapter_for_type("unknown")
    end

    test "works with atom types by converting to string" do
      assert {:ok, Flux.Sink.Adapters.HTTP} = Sink.adapter_for_type(:http)
      assert {:ok, Flux.Sink.Adapters.Stub} = Sink.adapter_for_type(:s3)
      assert {:ok, Flux.Sink.Adapters.Postgres} = Sink.adapter_for_type(:postgres)
      assert {:ok, Flux.Sink.Adapters.MySQL} = Sink.adapter_for_type(:mysql)
    end

    test "returns error for unknown atom type" do
      assert {:error, :unknown_type} = Sink.adapter_for_type(:unknown)
    end
  end

  describe "available_types/0" do
    test "returns all sink types sorted alphabetically" do
      assert Sink.available_types() ==
               [
                 "bigquery",
                 "http",
                 "kafka",
                 "mongodb",
                 "mysql",
                 "postgres",
                 "redis",
                 "s3",
                 "slack",
                 "snowflake"
               ]
    end
  end

  describe "deliver/3" do
    test "returns error when config has no type key" do
      config = %{"url" => "https://example.com"}
      assert {:error, {:missing_type, ^config}} = Sink.deliver(%{event: "test"}, config)
    end

    test "returns error for unknown sink type" do
      config = %{"type" => "unknown"}
      assert {:error, {:unknown_sink_type, "unknown"}} = Sink.deliver(%{event: "test"}, config)
    end

    test "Community bigquery delivery returns pro_required error" do
      config = %{"type" => "bigquery", "project_id" => "p", "dataset" => "d", "table" => "t"}
      assert {:error, {:pro_required, :bigquery_sink}} = Sink.deliver(%{event: "test"}, config)
    end
  end

  describe "validate_config/2" do
    test "delegates to HTTP adapter for valid config" do
      assert :ok = Sink.validate_config("http", %{"url" => "https://example.com/webhook"})
    end

    test "delegates to HTTP adapter and returns errors" do
      assert {:error, errors} = Sink.validate_config("http", %{})
      assert "url is required" in errors
    end

    test "Community s3 delegates to Stub and returns pro_required error" do
      config = %{"bucket" => "my-bucket", "key_template" => "data/{id}.json"}
      assert {:error, [msg]} = Sink.validate_config("s3", config)
      assert msg =~ "Flux Pro"
    end

    test "Community bigquery delegates to Stub and returns pro_required error" do
      config = %{"project_id" => "p", "dataset" => "d", "table" => "t"}
      assert {:error, [msg]} = Sink.validate_config("bigquery", config)
      assert msg =~ "Flux Pro"
    end

    test "delegates to Postgres adapter for valid config" do
      config = %{"table" => "events", "columns" => %{"type" => "event_type"}}
      assert :ok = Sink.validate_config("postgres", config)
    end

    test "delegates to MySQL adapter for valid config" do
      config = %{
        "database_url" => "mysql://user:pass@host:3306/db",
        "table" => "events",
        "columns" => %{"type" => "event_type"}
      }

      assert :ok = Sink.validate_config("mysql", config)
    end

    test "returns error for unknown sink type" do
      assert {:error, ["unknown sink type: unknown"]} =
               Sink.validate_config("unknown", %{})
    end
  end

  describe "test_connection/2" do
    test "returns error for unknown sink type" do
      assert {:error, {:unknown_sink_type, "unknown"}} =
               Sink.test_connection("unknown", %{})
    end
  end
end
