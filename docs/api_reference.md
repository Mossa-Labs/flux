# Flux API Reference

This document covers the external HTTP API for integrating with Flux.

---

## Table of Contents

- [Authentication](#authentication)
- [Endpoints](#endpoints)
  - [POST /api/webhooks/:source](#post-apiwebhookssource)
- [Message Structure](#message-structure)

---

## Authentication

All API requests require an `X-API-Key` header. The key is configured via application config:

```elixir
config :flux, FluxWeb.Plugs.ApiAuth,
  api_key: "your-secret-api-key"
```

In production, set the `FLUX_API_KEY` environment variable (loaded in `config/runtime.exs`).

### Error Responses

| Status | Error | Message | Cause |
|--------|-------|---------|-------|
| 401 | `Missing API key` | `X-API-Key header is required` | Request has no `X-API-Key` header |
| 401 | `Invalid API key` | `The provided API key is invalid` | Key does not match configured value |
| 500 | `Configuration error` | `API authentication not configured` | No API key configured on the server |

All error responses return JSON:

```json
{
  "error": "<error>",
  "message": "<message>"
}
```

---

## Endpoints

### POST /api/webhooks/:source

Accept a JSON payload from an external source and publish it to the queue for pipeline processing.

#### URL Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `source` | string | Source identifier (e.g., `github`, `stripe`, `custom`). Determines the queue name: `webhooks.<source>` |

#### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-API-Key` | Yes | API authentication key |
| `Content-Type` | Yes | Must be `application/json` |
| `X-Correlation-ID` | No | Correlation ID for request tracing (propagated to the message) |

#### Request Body

Arbitrary JSON payload. The entire body becomes the message payload.

#### Responses

**202 Accepted** -- Message queued successfully:

```json
{
  "status": "accepted",
  "message_id": "a1b2c3d4e5f6g7h8i9j0kw",
  "queue": "webhooks.github"
}
```

**500 Internal Server Error** -- Queue publish failed:

```json
{
  "status": "error",
  "message": "Failed to queue message"
}
```

#### Examples

**Basic webhook:**

```bash
curl -X POST http://localhost:4000/api/webhooks/github \
  -H "Content-Type: application/json" \
  -H "X-API-Key: dev-api-key" \
  -d '{"event": "push", "ref": "refs/heads/main"}'
```

**With correlation ID:**

```bash
curl -X POST http://localhost:4000/api/webhooks/stripe \
  -H "Content-Type: application/json" \
  -H "X-API-Key: dev-api-key" \
  -H "X-Correlation-ID: req-12345" \
  -d '{"type": "payment_intent.succeeded", "amount": 2000}'
```

**Missing API key (returns 401):**

```bash
curl -X POST http://localhost:4000/api/webhooks/test \
  -H "Content-Type: application/json" \
  -d '{"event": "test"}'
```

---

## Message Structure

When a webhook is received, Flux creates a `Flux.Queue.Message` struct with the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Base64url-encoded 16-byte random ID |
| `payload` | map | The original JSON request body |
| `source` | string | Source identifier from the URL (e.g., `github`) |
| `correlation_id` | string \| nil | Value of `X-Correlation-ID` header, or `nil` |
| `metadata` | map | Auto-populated request metadata (see below) |
| `inserted_at` | DateTime | UTC timestamp when the message was created |
| `adapter_meta` | map | Adapter-specific metadata (e.g., RabbitMQ `delivery_tag`) |

### Metadata Fields

The `metadata` map is automatically populated from the incoming HTTP request:

| Key | Description |
|-----|-------------|
| `remote_ip` | Client IP address |
| `user_agent` | `User-Agent` header value |
| `content_type` | `Content-Type` header value |
| `received_at` | ISO 8601 timestamp of receipt |

### Queue Routing

Messages are published to a queue named `webhooks.<source>`, where `<source>` is the URL parameter. For example:

- `POST /api/webhooks/github` publishes to queue `webhooks.github`
- `POST /api/webhooks/stripe` publishes to queue `webhooks.stripe`

Pipelines consume from these queues by setting their `source_queue` field to match (e.g., `webhooks.github`).
