defmodule FluxWeb.API.WebhookControllerTest do
  use FluxWeb.ConnCase, async: false

  alias Flux.Queue.Adapters.Memory

  setup do
    Memory.clear()
    :ok
  end

  describe "POST /api/webhooks/:source" do
    test "accepts valid JSON payload", %{conn: conn} do
      payload = %{"event" => "user.created", "data" => %{"id" => 123}}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", "test-api-key")
        |> post(~p"/api/webhooks/test_source", payload)

      assert %{"status" => "accepted", "message_id" => id, "queue" => queue} =
               json_response(conn, 202)

      assert is_binary(id)
      assert queue == "webhooks.test_source"

      # Verify message was published
      messages = Memory.get_messages("webhooks.test_source")
      assert length(messages) == 1
      assert hd(messages).source == "test_source"
    end

    test "includes correlation ID when provided", %{conn: conn} do
      correlation_id = "req-12345"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", "test-api-key")
        |> put_req_header("x-correlation-id", correlation_id)
        |> post(~p"/api/webhooks/github", %{"action" => "push"})

      assert json_response(conn, 202)

      [message] = Memory.get_messages("webhooks.github")
      assert message.correlation_id == correlation_id
    end

    test "captures request metadata", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", "test-api-key")
        |> put_req_header("user-agent", "TestAgent/1.0")
        |> post(~p"/api/webhooks/stripe", %{"type" => "payment.succeeded"})

      assert json_response(conn, 202)

      [message] = Memory.get_messages("webhooks.stripe")
      assert message.metadata.user_agent == "TestAgent/1.0"
      assert message.metadata.content_type == "application/json"
      assert is_binary(message.metadata.received_at)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/webhooks/test", %{"event" => "test"})

      assert json_response(conn, 401)["error"] == "Missing API key"
    end

    test "returns 401 with invalid API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", "invalid-key")
        |> post(~p"/api/webhooks/test", %{"event" => "test"})

      assert json_response(conn, 401)["error"] == "Invalid API key"
    end

    test "handles different source names", %{conn: _conn} do
      sources = ["github", "stripe", "custom-source", "source_with_underscores"]

      for source <- sources do
        Memory.clear()

        response_conn =
          build_conn()
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-api-key", "test-api-key")
          |> post(~p"/api/webhooks/#{source}", %{"test" => true})

        assert json_response(response_conn, 202)["queue"] == "webhooks.#{source}"
        assert length(Memory.get_messages("webhooks.#{source}")) == 1
      end
    end

    test "removes source from payload before publishing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-api-key", "test-api-key")
        |> post(~p"/api/webhooks/test", %{"event" => "created", "value" => 42})

      assert json_response(conn, 202)

      [message] = Memory.get_messages("webhooks.test")
      assert message.payload == %{"event" => "created", "value" => 42}
      refute Map.has_key?(message.payload, "source")
    end
  end
end
