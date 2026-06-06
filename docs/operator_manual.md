# Flux Operator Manual

This manual covers installation, configuration, operations, and troubleshooting for the Flux ETL/ELT platform.

---

## Table of Contents

- [System Requirements](#system-requirements)
- [Installation and Setup](#installation-and-setup)
- [Docker Compose](#docker-compose)
- [Configuration](#configuration)
- [Running in Production](#running-in-production)
- [Pipeline Operations](#pipeline-operations)
- [RBAC and Permissions](#rbac-and-permissions)
- [Monitoring and Observability](#monitoring-and-observability)
- [CI/CD](#cicd)
- [Troubleshooting](#troubleshooting)

---

## System Requirements

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| Elixir | 1.15+ | Compiled on Erlang/OTP 26+ |
| Erlang/OTP | 26+ | BEAM runtime |
| PostgreSQL | 18 | Primary datastore |
| Node.js | 18+ | Asset compilation (esbuild, Tailwind CSS) |

### Queue Adapter

Flux ships with an **in-memory queue adapter** (`Flux.Queue.Adapters.Memory`) across all environments. It provides fast, in-process message buffering with no external dependencies and is well-suited to single-node deployments. Durable, multi-node queue backends ship in the separate commercial edition.

---

## Installation and Setup

### 1. Clone the Repository

```bash
git clone <repository-url> flux
cd flux/app
```

### 2. Install Dependencies

```bash
mix deps.get
```

### 3. Database Setup

Ensure PostgreSQL is running, then create and migrate the database:

```bash
mix ecto.setup
```

This single command runs `ecto.create`, `ecto.migrate`, and `run priv/repo/seeds.exs`. Seeds create the following test data:

| Resource | Details |
|----------|---------|
| **Users** | `admin@flux.dev`, `member@flux.dev`, `viewer@flux.dev` (password: `password1234`) |
| **Organization** | Flux Development (slug: `flux-dev`) |
| **Teams** | Core, Analytics (under Flux Development) |
| **Team members** | Core: admin + member; Analytics: admin + viewer |

### 4. Asset Compilation

```bash
mix assets.setup
mix assets.build
```

### 5. Start the Server

```bash
mix phx.server
```

Or start in an interactive shell:

```bash
iex -S mix phx.server
```

The application is available at `http://localhost:4000`.

### Quick Start with `mix setup`

For a single-command setup that installs dependencies, creates the database, runs migrations, seeds data, and builds assets:

```bash
mix setup
```

### Environment Configuration (Development)

Development defaults are configured in `config/dev.exs`. You can override database settings with environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `postgres` | Database username |
| `POSTGRES_PASSWORD` | `postgres` | Database password |
| `POSTGRES_HOST` | `localhost` | Database hostname |
| `POSTGRES_DB` | `flux_dev` | Database name |

---

## Docker Compose

A `docker-compose.yml` at the repository root provides the full stack for local development:

```bash
docker compose up --build
```

### Services

| Service | Image | Ports | Purpose |
|---------|-------|-------|---------|
| `app` | Built from `app/Dockerfile` | `4000` | Phoenix server (auto-runs deps.get, ecto.create, ecto.migrate, phx.server) |
| `db` | `postgres:18-alpine` | `5432` | PostgreSQL database |

### Volumes

- `postgres_data` -- persists database data across restarts

### Health Checks

- **Postgres**: `pg_isready -U postgres` (5s interval, 5 retries)

The `app` service waits for `db` to pass its health check before starting.

### Common Commands

```bash
# Start all services in background
docker compose up -d

# View application logs
docker compose logs -f app

# Seed test data
docker compose exec app mix run priv/repo/seeds.exs

# Run tests inside the container
docker compose exec app mix test

# Open IEx shell
docker compose exec app iex -S mix

# Stop and remove volumes (fresh start)
docker compose down -v
```

---

## Configuration

### Queue Adapter

Flux uses an adapter pattern for its message queue. The Community edition ships the in-memory adapter, configured in `config/config.exs`:

```elixir
config :flux, Flux.Queue, adapter: Flux.Queue.Adapters.Memory
```

The memory adapter provides fast, in-process queuing with no external dependencies and is suitable for single-node deployments.

### RBAC Mode

Flux uses team-centric RBAC, configured at compile time:

```elixir
# config/config.exs
config :flux, rbac_mode: :team_centric
```

See [RBAC and Permissions](#rbac-and-permissions) for details.

### Oban Scheduler

Oban handles background job processing (e.g., outbound webhook delivery):

```elixir
# config/config.exs (base settings)
config :flux, Oban,
  repo: Flux.Repo,
  queues: [default: 10, webhooks: 20]
```

| Queue | Concurrency | Purpose |
|-------|-------------|---------|
| `default` | 10 | General background tasks |
| `webhooks` | 20 | Outbound webhook delivery |

---

## Running in Production

### Building a Release

```bash
MIX_ENV=prod mix release
```

### Required Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection URL (e.g., `ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Yes | Session signing key. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Yes | Public hostname for URL generation |
| `FLUX_API_KEY` | Yes | API authentication key for external integrations |
| `PHX_SERVER` | Yes | Set to `true` to start the HTTP server |
| `PORT` | No | HTTP port (default: `4000`) |
| `POOL_SIZE` | No | Database connection pool size (default: `10`) |
| `ECTO_IPV6` | No | Set to `true` or `1` to enable IPv6 for database connections |
| `DNS_CLUSTER_QUERY` | No | DNS query for cluster node discovery |

### Starting the Application

```bash
PHX_SERVER=true bin/flux start
```

### Production Architecture

Flux runs as a monolith containing all three subsystems:

```mermaid
graph TB
    subgraph "Flux Application (Monolith)"
        WEB[FluxWeb - Control Plane]
        ENGINE[FluxEngine - Data Plane]
        OBAN[Oban - Scheduler]
    end

    WEB --> DB[(PostgreSQL 18)]
    ENGINE --> DB
    OBAN --> DB

    style WEB fill:#4f46e5,color:#fff
    style ENGINE fill:#059669,color:#fff
    style OBAN fill:#d97706,color:#fff
```

Flux forms a cluster across nodes for high availability: the engine distributes pipeline supervision with Horde and aggregates metrics cluster-wide. Use `DNS_CLUSTER_QUERY` to enable automatic node discovery.

---

## Pipeline Operations

### Creating Pipelines

Pipelines are created and configured through the web UI:

1. Navigate to **Pipelines** in the sidebar.
2. Click **New Pipeline** to open the creation form.
3. Provide a name, optional description, and a **source queue** (the topic from which messages are consumed).
4. Use the **Visual Builder** at `/pipelines/builder` to construct transformation steps by dragging and connecting nodes on the canvas.
5. Save the pipeline. It starts in `stopped` status.

### Pipeline Statuses

| Status | Description |
|--------|-------------|
| `active` | Pipeline is running and processing messages from its source queue |
| `paused` | Pipeline is temporarily suspended; no new messages are consumed |
| `stopped` | Pipeline is inactive; must be explicitly started |

Active pipelines auto-start when the application boots. The `Flux.Pipeline.Manager` process queries all pipelines with `status = "active"` and spawns runners under the `Flux.Pipeline.DynamicSupervisor`.

### Source Queues and Message Routing

Each pipeline has a `source_queue` field identifying the topic it consumes from (e.g., `webhooks.github`). Messages are published to queues when external systems send webhooks to the FluxWeb endpoint, which validates and publishes payloads to the appropriate queue.

### Pipeline JSON IR Format

Pipelines use a JSON-based Intermediate Representation (IR) that decouples the UI builder from the execution engine:

```json
{
  "version": "1.0",
  "steps": [
    {"id": "s1", "type": "native", "operation": "rename", "config": {"from": "old_name", "to": "new_name"}},
    {"id": "s2", "type": "native", "operation": "filter", "config": {"field": "status", "operator": "eq", "value": "active"}},
    {"id": "s3", "type": "script", "language": "lua", "code": "function transform(data) ... end", "timeout_ms": 5000}
  ]
}
```

### Transformation Steps

#### Filter

Keeps or drops messages based on field conditions. Supports dot-notation for nested fields.

| Config Key | Type | Description |
|------------|------|-------------|
| `field` | string | Field path to evaluate (e.g., `"data.user.status"`) |
| `operator` | string | Comparison operator |
| `value` | any | Comparison value (for single-value operators) |
| `values` | list | Comparison values (for `in` / `not_in`) |

**Supported operators**: `eq`, `ne`, `in`, `not_in`, `gt`, `gte`, `lt`, `lte`, `contains`, `matches`

#### Map

Extracts a value from a source field (dot-notation) and writes it to a target field.

| Config Key | Type | Description |
|------------|------|-------------|
| `field` | string | Source field path |
| `to` | string | Target field name |
| `default` | any | Fallback value if source is nil (optional) |

#### Rename

Renames a field in the data map. If the source field does not exist, the data passes through unchanged.

| Config Key | Type | Description |
|------------|------|-------------|
| `from` | string | Original field name |
| `to` | string | New field name |

#### Script (Lua)

Executes user-defined Lua code in a sandboxed environment. The script must define a `transform(data)` function that receives and returns a Lua table. Dangerous standard library functions (file I/O, `os.execute`, `require`, etc.) are disabled.

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `code` | string | required | Lua source code |
| `timeout_ms` | integer | `5000` | Maximum execution time in milliseconds |

See [docs/lua_scripting.md](lua_scripting.md) for detailed examples and the list of available/restricted functions.

### Configuring Sinks

Sinks are output destinations where processed pipeline data is delivered. Configure sinks under **Sinks** in the sidebar.

#### HTTP Sink

Delivers data as HTTP POST requests (webhooks).

| Config Key | Description |
|------------|-------------|
| `url` | Destination URL |
| `headers` | Optional HTTP headers map |

#### Postgres Sink

Inserts data directly into a PostgreSQL table.

| Config Key | Description |
|------------|-------------|
| `url` | Database connection URL |
| `table` | Target table name |
| `columns` | Column mapping configuration |

Each sink has the following schema properties:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique name within the organization |
| `description` | string | Optional description |
| `type` | string | One of: `http`, `postgres` |
| `config` | map | Type-specific configuration |
| `enabled` | boolean | Whether the sink is active (default: `true`) |

### Ingesting Data via Webhooks

Flux ingests data through webhook (push) sources. External systems POST payloads to the FluxWeb webhook endpoint, which validates and publishes them to the target queue for pipeline processing. Set a pipeline's `source_queue` to the queue its webhook publishes to (e.g., `webhooks.github`).

---

## RBAC and Permissions

### Role Hierarchy

Flux implements four roles, from most to least privileged:

```
owner > admin > member > viewer
```

### Permission Matrix

| Action | Owner | Admin | Member | Viewer |
|--------|:-----:|:-----:|:------:|:------:|
| View pipelines | Yes | Yes | Yes | Yes |
| Create pipeline | Yes | Yes | Yes | -- |
| Edit pipeline | Yes | Yes | Yes | -- |
| Delete pipeline | Yes | Yes | -- | -- |
| Run pipeline | Yes | Yes | Yes | -- |
| View sinks | Yes | Yes | Yes | Yes |
| Create sink | Yes | Yes | Yes | -- |
| Edit sink | Yes | Yes | Yes | -- |
| Delete sink | Yes | Yes | -- | -- |
| View dashboard | Yes | Yes | Yes | Yes |
| Manage teams | Yes | Yes | -- | -- |
| View members | Yes | Yes | Yes | Yes |
| Invite member | Yes | Yes | -- | -- |
| Change member role | Yes | Yes | -- | -- |
| Remove member | Yes | Yes | -- | -- |
| Manage organization | Yes | Yes | -- | -- |
| View system settings | Yes | -- | -- | -- |

### Team-Centric RBAC

```elixir
config :flux, rbac_mode: :team_centric
```

- Organization access and roles are **derived from team memberships**.
- The user's effective organization role is their **highest role** across all team memberships in that organization (e.g., if a user is `admin` in one team and `member` in another, their org role is `admin`).
- A default organization (from seeds) is used when a user has no team memberships.

RBAC produces a `Flux.Accounts.Scope` struct and exposes the `Flux.Permissions.can?/3` API for permission checks throughout the application.

---

## Monitoring and Observability

### Dashboard Metrics

The Flux dashboard provides real-time metrics powered by the `Flux.Pipeline.Metrics` GenServer, which subscribes to telemetry events and broadcasts updates every 2 seconds via Phoenix PubSub.

| Metric | Description |
|--------|-------------|
| **Events/sec** | Rolling throughput over a 60-second sliding window |
| **Active Pipelines** | Count of pipelines with `status = "active"` |
| **Processed Total** | Cumulative messages successfully processed |
| **Failed Total** | Cumulative messages that failed processing |
| **Skipped Total** | Cumulative messages skipped by filter steps |

Per-pipeline metrics include processed count, failed count, skipped count, and total processing duration. In a cluster, metrics are aggregated cluster-wide.

### Metrics Internals

The `Flux.Pipeline.Metrics` GenServer drives the dashboard's real-time updates:

| Parameter | Value | Description |
|-----------|-------|-------------|
| Sliding window | 60 seconds | Events older than 60s are pruned from throughput calculation |
| Broadcast interval | 2 seconds | Metrics snapshot pushed to LiveView via PubSub every 2s |
| PubSub topic | `pipeline_metrics` | Subscribe with `Phoenix.PubSub.subscribe(Flux.PubSub, "pipeline_metrics")` |

**Telemetry event flow:**

```mermaid
graph LR
    R[Pipeline Runner] -->|emit| T[Telemetry Event]
    T -->|attach| M[Metrics GenServer]
    M -->|broadcast every 2s| PS[Phoenix PubSub]
    PS -->|push| LV[Dashboard LiveView]
```

1. `Pipeline.Runner` emits telemetry events (`:processed`, `:failed`, `:skipped`) after each message.
2. `Metrics` GenServer handles events via attached telemetry handlers, updating in-memory counters.
3. Every 2 seconds, `Metrics` calculates throughput (events in the last 60s / 60), prunes the sliding window, and broadcasts a snapshot to `pipeline_metrics`.
4. Dashboard LiveView receives the broadcast and updates the UI in real time.

### Phoenix LiveDashboard

In development, Phoenix LiveDashboard is available at:

```
http://localhost:4000/dev/dashboard
```

It provides:

- Real-time BEAM VM metrics (memory, processes, IO)
- Ecto query statistics
- LiveView process inspection
- OS-level monitoring

### Telemetry Events

Flux emits the following telemetry events that can be consumed by external monitoring systems:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:flux, :pipeline, :message, :processed]` | `duration` | `pipeline_id` |
| `[:flux, :pipeline, :message, :failed]` | -- | `pipeline_id` |
| `[:flux, :pipeline, :message, :skipped]` | -- | `pipeline_id` |

These events are attached by `Flux.Pipeline.Metrics` at startup and can also be used to feed external observability tools (Prometheus, Datadog, etc.) via standard telemetry reporter libraries.

---

## CI/CD

### GitHub Actions

The repository includes a CI workflow at `.github/workflows/test.yml` that runs on every pull request to `main`.

**Pipeline steps:**

| Step | Command | Purpose |
|------|---------|---------|
| Checkout | `actions/checkout@v4` | Clone the repository |
| Setup Beam | `erlef/setup-beam@v1` | Install Elixir 1.19.4 + OTP 28.2 |
| Cache | `actions/cache@v4` | Cache `app/deps` and `app/_build` by `mix.lock` hash |
| Dependencies | `mix deps.get` | Fetch Elixir dependencies |
| Compile | `mix compile --warnings-as-errors` | Strict compilation (warnings fail the build) |
| Test | `mix test` | Run the full test suite |

**Services:** PostgreSQL 18-alpine runs as a sidecar with health checks. All mix commands execute in the `app/` working directory.

**Note:** There is no automated deployment step. Production releases are built manually with `MIX_ENV=prod mix release` (see [Running in Production](#running-in-production)).

---

## Troubleshooting

### Pipeline Will Not Start

**Symptom**: A pipeline remains in `stopped` or `paused` status and does not process messages.

**Resolution**:

1. Verify the pipeline status is `active` -- only active pipelines process messages.
2. Check the pipeline's `source_queue` exists and has messages.
3. Look at application logs for errors from `Flux.Pipeline.Runner` or `Flux.Pipeline.Manager`.
4. Verify the pipeline's JSON IR config is valid (has `version` and `steps` keys).
5. If steps reference sink IDs, confirm those sinks exist and are enabled.

### Sink Delivery Failures

**Symptom**: Processed data is not arriving at the configured destination.

**Resolution**:

1. Confirm the sink is enabled (`enabled: true`).
2. **HTTP sink**: Verify the destination URL is reachable. Check for HTTP status errors in logs.
3. **Postgres sink**: Verify the connection URL, ensure the target table exists, and check column mappings.
4. Use `Flux.Sink.test_connection/2` in an IEx session to validate connectivity:

   ```elixir
   Flux.Sink.test_connection("http", %{"url" => "https://example.com/webhook"})
   ```

### Debug Logging

Enable verbose logging for pipeline and sink operations by adjusting the Logger level:

```elixir
# In config/runtime.exs or at runtime via IEx
Logger.configure(level: :debug)
```

Pipeline processing steps and sink delivery emit `Logger.debug` messages with pipeline IDs and step details. In production, consider filtering by metadata rather than running the entire application at debug level.

### Database Connection Issues

**Symptom**: Application crashes or queries time out.

**Resolution**:

1. Verify PostgreSQL is running and accepting connections.
2. Check `DATABASE_URL` is correctly formatted: `ecto://USER:PASS@HOST:PORT/DATABASE`
3. Increase the `POOL_SIZE` environment variable if the application is under high concurrency.
4. If using IPv6, set `ECTO_IPV6=true`.
5. Check for long-running queries in PostgreSQL: `SELECT * FROM pg_stat_activity WHERE state = 'active';`

### Lua Script Errors

**Symptom**: Pipeline fails at a script step.

**Resolution**:

1. Check logs for the specific Lua error message (syntax error, runtime error, or timeout).
2. Test scripts interactively in IEx:

   ```elixir
   alias Flux.Pipeline.Steps.Script

   data = %{"field" => "value"}
   config = %{"code" => "function transform(data) return data end", "timeout_ms" => 5000}

   Script.execute(data, config)
   ```

3. Increase `timeout_ms` if the script performs complex computations.
4. Ensure the `transform` function returns a table (not `nil` or a scalar value).
5. Review [docs/lua_scripting.md](lua_scripting.md) for the list of restricted standard library functions.

### Application Will Not Compile

**Symptom**: `mix compile` fails with dependency or version errors.

**Resolution**:

1. Ensure Elixir and Erlang versions meet the [system requirements](#system-requirements).
2. Run `mix deps.get` to fetch missing dependencies.
3. If dependency conflicts occur, run `mix deps.update --all` (use cautiously in production).
4. For asset compilation issues, run `mix assets.setup` to install esbuild and Tailwind.
