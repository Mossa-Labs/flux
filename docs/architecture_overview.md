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
*   **Tech**: Broadway, **Oban (Scheduler)**.
*   **Responsibilities**:
    *   Ingestion.
    *   Buffering & Flow Control.
    *   Transformation & Enrichment.
    *   Reliable Delivery (Sinks).

---

## Core Components

### A. Ingestion Layer
Flux ingests data via **push**: external systems send generic Webhooks (JSON/XML) to the `FluxWeb.Endpoint`. Payloads are immediately validated and published to the **Queue Adapter**.

### B. Buffering & Queue Adapter
Flux uses an **Adapter Pattern** for buffering so the queue backend is pluggable. The Community edition ships the **in-memory adapter** (`Flux.Queue.Adapters.Memory`), which uses fast in-memory polling / PubSub — ideal for development and single-node deployments. Adapters are registered at boot in `Flux.Registrations` and looked up by string type through `Flux.Queue.Registry`, so additional backends can be registered without changing the engine.

### C. Pipeline Engine (Broadway)
Each user-defined pipeline spawns a dedicated supervised Broadway tree.
*   **Producer**: Consumes from the configured queue.
*   **Processors (Concurrency: High)** execute the pipeline's steps:
    1.  **Map / Rename**: Rename keys, cast types, deep merge.
    2.  **Filter**: Drop records that don't match a predicate.
    3.  **Script**: User-defined Lua logic for safe custom transformations, run in the `Luerl` sandbox.
*   **Batcher**: Aggregates records for efficient bulk writing.
*   **Consumer**: Writes to the configured destination via a sink adapter (HTTP, Postgres).

### D. Visual Builder & Execution Strategy (Hybrid IR)
Flux uses a **JSON-based Intermediate Representation (IR)** to decouple the UI from execution.
*   **CSS Framework**: **Tailwind CSS v4** for high-performance styling.
*   **Frontend (React Flow)** — *only* for the pipeline builder canvas/flow chart:
    *   **Lazy Loading**: React and React Flow are **only loaded** on the Builder route (`/pipelines/builder`). They are not bundled into the main `app.js`.
    *   **Integration**: Embedded via Phoenix Client Hook (`<div phx-hook="VisualBuilder" ...>`).
    *   **Round-Trip**: Generates strictly typed JSON configuration.
    *   All other UI in the app is built with LiveView and Phoenix UI tooling (see Control Plane UI stack above).
*   **Backend (Hybrid Execution)**:
    *   The `FluxEngine` iterates through this JSON list.
    *   **Native Steps**: Common ops (Map, Filter, Rename) are executed as compiled Elixir code for maximum speed.
    *   **Script Steps**: Custom logic nodes are executed via the `Luerl` sandbox.
    *   **Benefit**: This allows "Round-Tripping" (Edit UI → Save JSON → Load UI) without complex code parsing.

### E. Extensibility
Sinks, queues, and pipeline steps are **behaviours** resolved through **registries** at runtime, never hard-coded in the engine. Community adapters self-register at boot in `Flux.Registrations`. See [`developer_guide.md`](developer_guide.md) for how to add your own, and [`architecture/open_core.md`](architecture/open_core.md) for the extension model.

---

## Data Model (Postgres 18)

*   `organizations`: Top-level tenant (creator via `user_id`).
*   `teams`: Sub-groups within organizations (`organization_id`, creator `user_id`).
*   `team_members`: User–team membership and role (admin, member, viewer); used for access and for org role derivation.
*   `pipelines`: Configuration definitions (JSONB).
*   `pipeline_runs`: Audit log of execution batches.

### Authorization and RBAC

*   **Team-centric**: Scope and roles are derived from `teams` and `team_members` — self-hosted deployments use this without managing separate org membership.
*   **Scope** (see `Flux.Accounts.Scope`): `user`, `organization_id`, `organization_role`.
*   **Permission API**: `Flux.Permissions.can?(scope, action, resource)` — use in LiveViews, contexts, and layout to allow or forbid actions by role.

See [`rbac.md`](rbac.md) for details.

## Deployment Strategy
*   **Containerization**: Docker / Docker Compose.
*   **Orchestration**: Self-hosted (instances) or Kubernetes.
*   **Services**:
    *   `app` (**Monolith**): Contains `FluxWeb` (UI), `FluxEngine` (Broadway), and `Oban` (Scheduler).
        *   *Note*: The Community edition runs as a single node. Multi-node horizontal scaling and high availability ship in the commercial (Pro/Enterprise) edition.
    *   `db` (Postgres 18): Stores App Data, Pipeline Configs, and Oban Jobs.
