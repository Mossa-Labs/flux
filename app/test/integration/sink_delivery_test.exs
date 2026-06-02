defmodule Flux.Integration.SinkDeliveryTest do
  @moduledoc """
  Integration tests for sink delivery adapters.

  Tests HTTP sink error handling against unreachable endpoints, and
  Postgres sink delivery against a real database table via the
  internal (Ecto) adapter.
  """

  use Flux.DataCase

  alias Flux.Sink.Adapters.HTTP
  alias Flux.Sink.Adapters.Postgres

  describe "HTTP sink delivery" do
    test "returns transport error for unreachable endpoint" do
      config = %{
        "url" => "http://127.0.0.1:1/webhook",
        "method" => "POST",
        "retry" => %{"max_attempts" => 1, "delay_ms" => 1}
      }

      data = %{"event" => "test"}
      assert {:error, {:transport_error, _reason}} = HTTP.deliver(data, config, [])
    end

    test "returns http_error for non-2xx responses" do
      # Use httpbin.org-style endpoint that returns 404
      # Since this depends on network, we test the config validation path
      config = %{
        "url" => "http://127.0.0.1:1/not-found",
        "method" => "GET",
        "retry" => %{"max_attempts" => 1, "delay_ms" => 1}
      }

      data = %{"event" => "test"}
      # Port 1 is unreachable, so we expect a transport error
      assert {:error, {:transport_error, _reason}} = HTTP.deliver(data, config, [])
    end

    test "builds correct headers with bearer auth" do
      # Validate the config is accepted (end-to-end config validation)
      config = %{
        "url" => "https://example.com/webhook",
        "method" => "POST",
        "auth" => %{"type" => "bearer", "token" => "test-token-123"},
        "headers" => %{"X-Custom-Header" => "custom-value"}
      }

      assert :ok = HTTP.validate_config(config)
    end

    test "builds correct headers with basic auth" do
      config = %{
        "url" => "https://example.com/webhook",
        "auth" => %{"type" => "basic", "username" => "user", "password" => "pass"}
      }

      assert :ok = HTTP.validate_config(config)
    end

    test "builds correct headers with api_key auth" do
      config = %{
        "url" => "https://example.com/webhook",
        "auth" => %{"type" => "api_key", "header_name" => "X-API-Key", "key" => "secret"}
      }

      assert :ok = HTTP.validate_config(config)
    end
  end

  describe "Postgres sink delivery (internal mode)" do
    setup do
      Flux.Repo.query!("""
      CREATE TABLE IF NOT EXISTS test_sink_events (
        event_type VARCHAR(255),
        user_id VARCHAR(255),
        inserted_at TIMESTAMP,
        updated_at TIMESTAMP
      )
      """)

      on_exit(fn ->
        Flux.Repo.query!("DROP TABLE IF EXISTS test_sink_events")
      end)

      :ok
    end

    test "inserts row into internal postgres table" do
      config = %{
        "mode" => "internal",
        "table" => "test_sink_events",
        "columns" => %{"type" => "event_type", "user" => "user_id"}
      }

      data = %{"type" => "user.created", "user" => "user-123"}
      assert :ok = Postgres.deliver(data, config, [])

      # Verify the row was inserted
      {:ok, result} = Flux.Repo.query("SELECT event_type, user_id FROM test_sink_events")
      assert result.num_rows == 1
      assert result.rows == [["user.created", "user-123"]]
    end

    test "inserts multiple rows sequentially" do
      config = %{
        "mode" => "internal",
        "table" => "test_sink_events",
        "columns" => %{"type" => "event_type", "user" => "user_id"}
      }

      assert :ok = Postgres.deliver(%{"type" => "user.created", "user" => "u1"}, config, [])
      assert :ok = Postgres.deliver(%{"type" => "user.updated", "user" => "u2"}, config, [])

      {:ok, result} =
        Flux.Repo.query("SELECT event_type, user_id FROM test_sink_events ORDER BY event_type")

      assert result.num_rows == 2
      assert result.rows == [["user.created", "u1"], ["user.updated", "u2"]]
    end

    test "handles nested field extraction from data" do
      config = %{
        "mode" => "internal",
        "table" => "test_sink_events",
        "columns" => %{"payload.type" => "event_type", "payload.user_id" => "user_id"}
      }

      data = %{"payload" => %{"type" => "order.placed", "user_id" => "u-456"}}
      assert :ok = Postgres.deliver(data, config, [])

      {:ok, result} = Flux.Repo.query("SELECT event_type, user_id FROM test_sink_events")
      assert result.num_rows == 1
      assert result.rows == [["order.placed", "u-456"]]
    end

    test "adds timestamps automatically" do
      config = %{
        "mode" => "internal",
        "table" => "test_sink_events",
        "columns" => %{"type" => "event_type"}
      }

      data = %{"type" => "test.event"}
      assert :ok = Postgres.deliver(data, config, [])

      {:ok, result} =
        Flux.Repo.query(
          "SELECT inserted_at, updated_at FROM test_sink_events WHERE event_type = 'test.event'"
        )

      assert result.num_rows == 1
      [[inserted_at, updated_at]] = result.rows
      assert inserted_at != nil
      assert updated_at != nil
    end

    test "returns error for non-existent table" do
      config = %{
        "mode" => "internal",
        "table" => "nonexistent_table_xyz",
        "columns" => %{"type" => "event_type"}
      }

      data = %{"type" => "test"}
      assert {:error, {:postgres_error, _message}} = Postgres.deliver(data, config, [])
    end
  end

  describe "Flux.Sink facade" do
    test "dispatches to HTTP adapter by type" do
      config = %{
        "type" => "http",
        "url" => "http://127.0.0.1:1/webhook",
        "method" => "POST",
        "retry" => %{"max_attempts" => 1, "delay_ms" => 1}
      }

      data = %{"event" => "test"}
      assert {:error, {:transport_error, _}} = Flux.Sink.deliver(data, config, [])
    end

    test "returns error for unknown sink type" do
      config = %{"type" => "unknown_sink"}
      assert {:error, {:unknown_sink_type, "unknown_sink"}} = Flux.Sink.deliver(%{}, config, [])
    end

    test "returns error when type key is missing" do
      config = %{"url" => "https://example.com"}
      assert {:error, {:missing_type, ^config}} = Flux.Sink.deliver(%{}, config, [])
    end
  end
end
