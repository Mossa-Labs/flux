defmodule FluxWeb.API.WebhookController do
  @moduledoc """
  Handles incoming webhook payloads and publishes them to the queue.

  ## Endpoints

    * `POST /api/webhooks/:source` - Accept JSON payload from the specified source

  ## Headers

    * `X-API-Key` (required) - API key for authentication
    * `X-Correlation-ID` (optional) - Correlation ID for request tracing

  """

  use FluxWeb, :controller

  alias Flux.Queue
  alias Flux.Queue.Message

  require Logger

  @doc """
  Receives a webhook payload and publishes it to the queue.

  ## Parameters

    * `source` - The source identifier (e.g., "github", "stripe", "custom")
    * Request body - The JSON payload

  ## Response

    * 202 Accepted - Message queued successfully
    * 400 Bad Request - Invalid payload
    * 500 Internal Server Error - Queue publish failed

  """
  def create(conn, %{"source" => source} = params) do
    payload = Map.delete(params, "source")
    correlation_id = get_correlation_id(conn)

    message =
      Message.new(payload,
        source: source,
        correlation_id: correlation_id,
        metadata: build_metadata(conn)
      )

    queue_name = "webhooks.#{source}"

    case Queue.publish(queue_name, message) do
      :ok ->
        Logger.info("Webhook received",
          source: source,
          message_id: message.id,
          correlation_id: correlation_id
        )

        conn
        |> put_status(:accepted)
        |> json(%{
          status: "accepted",
          message_id: message.id,
          queue: queue_name
        })

      {:error, reason} ->
        Logger.error("Failed to publish webhook",
          source: source,
          reason: inspect(reason)
        )

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to queue message"
        })
    end
  end

  defp get_correlation_id(conn) do
    case get_req_header(conn, "x-correlation-id") do
      [id | _] -> id
      _ -> nil
    end
  end

  defp build_metadata(conn) do
    %{
      remote_ip: format_ip(conn.remote_ip),
      user_agent: get_header(conn, "user-agent"),
      content_type: get_header(conn, "content-type"),
      received_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(ip), do: inspect(ip)

  defp get_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      _ -> nil
    end
  end
end
