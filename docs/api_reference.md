# Flux API Reference

This document covers the external HTTP API for integrating with Flux.

---

## Table of Contents

- [Authentication](#authentication)
- [Authorization](#authorization)
- [Endpoints](#endpoints)
  - [GET /health](#get-health)
  - [GET /api/pipelines](#get-apipipelines)
  - [POST /api/pipelines](#post-apipipelines)
  - [GET /api/pipelines/:id](#get-apipipelinesid)
  - [POST /api/pipelines/:id/start](#post-apipipelinesidstart)
  - [POST /api/pipelines/:id/stop](#post-apipipelinesidstop)
  - [GET /api/sinks](#get-apisinks)
  - [POST /api/webhooks/:source](#post-apiwebhookssource)
- [Message Structure](#message-structure)

---

## Authentication

All API requests except `GET /health` require an `X-API-Key` header carrying a
**per-organization API key**. Each key is bound to one organization, so requests
are automatically scoped to that organization's data.

Create and manage keys under **System Settings → API Keys**. A key looks like
`flux_pk_<random>` and is shown in full **once, at creation** — only a hash is
stored, so copy it then. Keys can be given an optional expiry and revoked at any
time.

```bash
curl http://localhost:4000/api/pipelines \
  -H "X-API-Key: flux_pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

> **Legacy global key (deprecated).** A single key configured via
> `config :flux, FluxWeb.Plugs.ApiAuth, api_key:` (or the `FLUX_API_KEY` env var)
> still authenticates during migration, scoped to the first organization, and
> logs a deprecation warning. Prefer per-organization keys.

### Error Responses

| Status | Error code | Cause |
|--------|------------|-------|
| 401 | `Missing API key` / `Invalid API key` | No key, or an unknown / revoked / expired key |
| 403 | `forbidden` | The key's role lacks permission for the action |
| 404 | `not_found` | Resource missing or not in the key's organization |
| 422 | `unprocessable_entity` | Validation failed (`details` lists field errors) |

All error responses return JSON:

```json
{ "error": "<code>", "message": "<message>" }
```

`422` responses include a `details` object keyed by field.

---

## Authorization

A key's access is the **intersection of its role and its scopes** — both must
allow a request, so scopes can narrow a key below its role but never widen it
past it.

### Role

A key carries a **role** (`admin`, `member`, or `viewer`) chosen at creation:

| Action | Minimum role |
|--------|--------------|
| List / read pipelines and sinks | `viewer` |
| Create a pipeline | `member` |
| Start / stop a pipeline | `member` |

### Scopes

A key also carries OAuth-style **scopes**. Each endpoint requires one; a request
missing it returns `403`. When scopes are omitted at creation they default to
the role's full set (so a key behaves like its role until you restrict it).

| Scope | Grants |
|-------|--------|
| `read:pipelines` | `GET /api/pipelines`, `GET /api/pipelines/:id` |
| `write:pipelines` | `POST /api/pipelines`, `…/start`, `…/stop` |
| `read:sinks` | `GET /api/sinks` |
| `write:sinks` | reserved for future sink-write endpoints |

Example: an `admin`-role key scoped to only `read:pipelines` can list pipelines
but is `403` on create and on `GET /api/sinks` — least-privilege automation.

Any request that exceeds the key's role **or** lacks the endpoint's scope
returns `403`.

---

## Endpoints

### GET /health

Unauthenticated health probe for load balancers. Returns `200` when the database
and queue are reachable, `503` otherwise.

```json
{ "status": "ok", "database": "connected", "queue": "connected", "version": "0.1.0" }
```

### GET /api/pipelines

Lists the organization's pipelines (summary view).

```json
{ "data": [
  { "id": 1, "name": "orders", "status": "active",
    "source_queue": "webhooks.orders", "sink_count": 2, "updated_at": "..." }
] }
```

### POST /api/pipelines

Creates a pipeline from a JSON IR body (the same format the visual builder
produces). The organization is taken from the API key — any `organization_id` in
the body is ignored. Requires the `member` role. Returns `201` with the created
pipeline, or `422` on validation errors.

```bash
curl -X POST http://localhost:4000/api/pipelines \
  -H "X-API-Key: flux_pk_..." -H "Content-Type: application/json" \
  -d '{"name":"orders","source_queue":"webhooks.orders",
       "steps":{"version":"1.0","steps":[]},"sink_ids":[]}'
```

### GET /api/pipelines/:id

Returns a pipeline's full detail — config, steps, sink ids, and a metrics
snapshot. `404` if the pipeline is not in the key's organization.

### POST /api/pipelines/:id/start

Starts (or resumes) a pipeline. Requires the `member` role. Returns the new
status:

```json
{ "data": { "id": 1, "status": "active" } }
```

### POST /api/pipelines/:id/stop

Stops a pipeline gracefully. Requires the `member` role. Returns
`{ "data": { "id": 1, "status": "stopped" } }`.

### GET /api/sinks

Lists the organization's sinks. **Secret config fields** (auth tokens,
passwords, usernames, keys) are replaced with `"[REDACTED]"` in the response.

```json
{ "data": [
  { "id": 1, "name": "warehouse", "type": "http", "enabled": true,
    "config": { "url": "https://...", "auth": { "type": "bearer", "token": "[REDACTED]" } },
    "updated_at": "..." }
] }
```

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
