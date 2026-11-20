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

  alias Flux.Observability.SchemaFingerprint
  alias Flux.Queue
  alias Flux.Queue.Message
  alias Flux.Source.Adapters.Webhook

  require Logger

  @doc """
  Receives a webhook payload and publishes it to the queue.

  ## Parameters

    * `source` - The source identifier (e.g., "github", "stripe", "custom")
    * Request body - The JSON payload

  ## Response

    * 202 Accepted - Message queued successfully
    * 400 Bad Request - Invalid payload, or a `source` that can't name a queue
    * 403 Forbidden - The API key isn't tied to an organization
    * 429 Too Many Requests - Organization is over its usage quota
    * 500 Internal Server Error - Queue publish failed

  The message is queued in the API key's organization only: only that
  organization's pipelines can consume it, whatever `source` is.
  """
  def create(conn, %{"source" => source} = params) do
    org_id = conn.assigns.current_scope.organization_id

    cond do
      not Webhook.valid_source?(source) -> invalid_source(conn)
      not (is_integer(org_id) and org_id > 0) -> organization_required(conn)
      true -> accept(conn, org_id, source, Map.delete(params, "source"))
    end
  end

  defp accept(conn, org_id, source, payload) do
    correlation_id = get_correlation_id(conn)

    message =
      Message.new(payload,
        source: source,
        organization_id: org_id,
        correlation_id: correlation_id,
        metadata: build_metadata(conn)
      )

    # Queue-name convention is owned by the Webhook source adapter so every
    # ingestion path derives it from one place (see Flux.Source.Adapters.Webhook).
    # The name is logical; Flux.Queue places it in the caller's organization.
    queue_name = Flux.Source.queue_name("webhook", %{"source" => source})

    # Usage quota is a Pro feature; the Community provider always returns `:ok`,
    # so ingestion is never throttled on Community.
    case Flux.Metering.check_quota(org_id) do
      :ok -> publish(conn, queue_name, message, source, org_id, correlation_id)
      {:error, {:quota_exceeded, retry_after}} -> quota_exceeded(conn, retry_after)
    end
  end

  defp invalid_source(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      error: "invalid_source",
      message:
        "source must start with a letter or digit and contain only letters, digits, '_', '.' and '-' (at most 128)"
    })
  end

  defp organization_required(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      status: "error",
      error: "organization_required",
      message: "This API key isn't tied to an organization"
    })
  end

  defp publish(conn, queue_name, message, source, org_id, correlation_id) do
    case Queue.publish(org_id, queue_name, message, []) do
      :ok ->
        # `messages_ingested` hook point: a Pro metering handler attaches here.
        :telemetry.execute(
          [:flux, :queue, :published],
          %{count: 1},
          %{organization_id: org_id, source: source, queue: queue_name}
        )

        # Schema-drift hook point: a Pro observability handler attaches here. The
        # raw payload never leaves this process — only a stable shape fingerprint
        # (top-level keys + value types) and the field count travel on the event.
        :telemetry.execute(
          [:flux, :webhook, :received],
          %{field_count: SchemaFingerprint.field_count(message.payload)},
          %{
            organization_id: org_id,
            source: source,
            fingerprint: SchemaFingerprint.compute(message.payload)
          }
        )

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

  defp quota_exceeded(conn, retry_after) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_status(:too_many_requests)
    |> json(%{
      status: "error",
      error: "quota_exceeded",
      message: "Usage quota exceeded for the current period",
      retry_after: retry_after
    })
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
