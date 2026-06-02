# Flux Architecture Overview

## Executive Summary
Flux is a self-hosted, high-performance ETL/ELT platform designed for dynamic data pipelining. It combines the reliability of the BEAM (Erlang VM) with modern stream processing capabilities to provide a robust "Data Mover" solution.

## High-Level Architecture
The system is composed of two primary planes:

### 1. Control Plane (FluxWeb)
*   **Role**: Management, Configuration, and Visibility.
*   **Tech**: Phoenix 1.8, LiveView, **Tailwind CSS v4**, Postgres 18.
*   **UI stack (Phoenix first, React only for builder)**:
    *   **Prefer Phoenix** for all UI: LiveView, LiveView function components, core components (`<.form>`, `<.input>`, `<.icon>`, `<.button>`, `<.modal>`, `<.table>`, etc.), Layouts, HEEx, `Phoenix.Component`, phx-hook, and Tailwind. Use these for new pages, forms, dashboards, and features.
    *   **Use React only** for the **canvas / flow chart** on `/pipelines/builder` (React Flow). React is not used elsewhere; no new React routes or app-wide React UI.
*   **Responsibilities**:
    *   User/Team Management (Multi-tenancy).
    *   Pipeline Configuration (Visual Builder).
    *   Real-time Metrics Dashboard (Phoenix PubSub).

### 2. Data Plane (FluxEngine)
*   **Role**: Execution and Processing.
*   **Tech**: Broadway, RabbitMQ/AMQP, **Oban (Scheduler)**, Nx.
*   **Responsibilities**:
    *   Ingestion (Push & Pull).
    *   Buffering & Flow Control.
    *   Transformation & Enrichment.
    *   Reliable Delivery (Sinks).

---

## Core Components

### A. Ingestion Layer
Flux supports two modes of data entry:
1.  **Push (Real-time)**:
    *   External systems send generic Webhooks (JSON/XML) to the `FluxWeb.Endpoint`.
    *   Payloads are immediately validated and published to the **Queue Adapter**.
2.  **Pull (Scheduled)**:
    *   Managed by **Oban**.
    *   Jobs run on defined Cron schedules to poll external sources (SFTP, S3, SQL).
    *   Fetched data is chunked and published to the **Queue Adapter**.

### B. Buffering & Queue Adapter
To support both Production reliability and Development simplicity, Flux uses an **Adapter Pattern**:
*   **Production**: `Flux.Queue.RabbitMQ`
    *   Uses AMQP 0-9-1.
    *   Provides durable persistence, back-pressure, and dlq (dead-letter queue) support.
*   **Testing/Lite**: `Flux.Queue.Memory`
    *   Uses fast in-memory generic polling or PubSub.

### C. Pipeline Engine (Broadway)
Each user-defined pipeline spawns a dedicated **DynamicSupervisor** tree.
*   **Producer**: Consumes from the specific Queue Topic.
*   **Processors (Concurrency: High)**:
    1.  **Structure Map**: Rename keys, cast types, deep merge.
    2.  **Luerl Script**: User-defined Lua logic for safe custom transformations.
    3.  **Enhancer**: HTTP lookups for data enrichment.
    4.  **AI Sentinel**: Nx-based signal processing (see below).
*   **Batcher**: Aggregates records for efficient bulk writing.
*   **Consumer**: Writes to final destination (S3, Postgres, Webhook).

### D. Visual Builder & Execution Strategy (Hybrid IR)
Flux uses a **JSON-based Intermediate Representation (IR)** to decouple the UI from execution.
*   **CSS Framework**: **Tailwind CSS v4** (Oxygen engine) for high-performance styling.
*   **Frontend (React Flow)** — *only* for the pipeline builder canvas/flow chart:
    *   **Lazy Loading**: React and React Flow are **only loaded** on the Builder route (`/pipelines/builder`). They are not bundled into the main `app.js`.
    *   **Integration**: Embedded via Phoenix Client Hook (`<div phx-hook="VisualBuilder" ...>`).
    *   **Round-Trip**: Generates strictly typed JSON configuration.
    *   All other UI in the app is built with LiveView and Phoenix UI tooling (see Control Plane UI stack above).
*   **Backend (Hybrid Execution)**:
    *   The `FluxEngine` iterates through this JSON list.
    *   **Native Steps**: Common ops (Map, Filter, Rename) are executed as compiled Elixir code for maximum speed.
    *   **Script Steps**: Custom logic nodes are executed via the `Luerl` sandbox.
    *   **Benefit**: This allows "Round-Tripping" (Edit UI \u2192 Save JSON \u2192 Load UI) without complex code parsing.

### E. Intelligence Layer (AI)
*   **Library**: `Nx` (Numerical Elixir) + `Bumblebee` (optional future).
*   **Function**:
    *   Maintains sliding windows of metric statistics (Payload size, Value distributions).
    *   Detects anomalies (Z-Score spikes, Drift).
    *   Tags records as `{:anomaly, score}` for routing to alert queues.

---

## Data Model (Postgres 18)

*   `organizations`: Top-level tenant (creator via `user_id`).
*   `organization_members`: (Optional) Org membership and role when `:rbac_mode` is `:org_centric`; used for RBAC and default org resolution.
*   `teams`: Sub-groups within organizations (`organization_id`, creator `user_id`).
*   `team_members`: User–team membership and role (admin, member, viewer); used for access and, when `:rbac_mode` is `:team_centric`, for org role derivation.
*   `pipelines`: Configuration definitions (JSONB).
*   `pipeline_runs`: Audit log of execution batches.
*   `signals`: Stored anomaly events for analysis.

### Authorization and RBAC

*   **Config**: `config :flux, :rbac_mode, :org_centric | :team_centric` (default `:team_centric`).
*   **Org-centric**: Scope and roles come from `organization_members`; cloud / multi-tenant.
*   **Team-centric**: Scope and roles are derived from `teams` and `team_members`; self-hosted can use this without managing org members.
*   **Scope** (see `Flux.Accounts.Scope`): `user`, `organization_id`, `organization_role`. Same struct in both modes; only the source of org/role differs.
*   **Permission API**: `Flux.Permissions.can?(scope, action, resource)` — use in LiveViews, contexts, and layout to allow or forbid actions by role.

## Deployment Strategy
*   **Containerization**: Docker / Docker Compose.
*   **Orchestration**: Self-hosted (instances) or Kubernetes.
*   **Services**:
    *   `app` (**Monolith**): Contains `FluxWeb` (UI), `FluxEngine` (Broadway), and `Oban` (Scheduler).
        *   *Note*: Can be split into distinct `web` and `worker` containers for scaling if required.
    *   `db` (Postgres 18): Stores App Data, Pipeline Configs, and Oban Jobs.
    *   `broker` (RabbitMQ): Durable message buffer for pipeline events.
