# Flux Development Roadmap (Archived)

> **Archived**: This planning document is historical. All planned features have been implemented. See [architecture_overview.md](../architecture_overview.md) and [operator_manual.md](../operator_manual.md) for current documentation.

This document outlines the iterative implementation plan for Flux. Each iteration is designed to deliver a testable, working system.

## Iteration 1: The Core Foundation
**Goal**: Initialize the system and establish the multi-tenant data model.
*   [ ] **Project Init**: Generate Phoenix 1.8 app with Postgres 18 and Docker Compose.
*   [ ] **Identity & Access**: Implement `Organizations`, `Teams`, and `Users` schemas.
*   [ ] **Authentication**: Simple Email/Password login (or AshAuth) scoped to Organizations.
*   [ ] **Dashboard Shell**: Basic LiveView layout with Sidebar navigation.

## Iteration 2: Ingestion & Buffering
**Goal**: Get data *IN* reliably (Push & Pull).
*   [ ] **Queue Adapter**: Implement `Flux.Queue` behaviour with `RabbitMQ` and `Memory` adapters.
*   [ ] **Webhook Source**: Create an API endpoint that accepts JSON and publishes to the Queue.
*   [ ] **Scheduler (Oban)**: Configure Oban and create a `Flux.Workers.Poller` job for scheduled fetches.
*   [ ] **Verification**: Send a cURL request \u2192 Verify message appears in RabbitMQ UI.

## Iteration 3: The Engine & Intelligence
**Goal**: Process data with Broadway and apply Transformations + AI.
*   [ ] **Dynamic Broadway**: Create the generic `Flux.Pipeline.Runner` module.
*   [ ] **Hybrid Execution Engine**:
    *   Implement the **JSON IR Interpreter** (iterating through steps).
    *   Implement "Native Steps" (Map, Rename, Filter) in Elixir.
    *   Integrate `Luerl` (Lua) sandbox for "Script Steps".
*   [ ] **AI Sentinel**: Implement `Flux.AI.Detector` using Nx for anomaly scoring.
*   [ ] **Pipeline Supervisor**: Logic to start/stop Broadway pipelines based on DB Context.

## Iteration 4: Sinks & Outputs
**Goal**: Get data *OUT* to destinations.
*   [ ] **Sinks**: Implement Adaptors for:
    *   `S3` / `MinIO` (using `ExAws`).
    *   `Http` (Webhook egress).
    *   `Postgres/SQL` (Generic Insert).
*   [ ] **Visual Builder (React Flow)**:
    *   **Architecture**: "Island" strategy. Only load React bundle on `/pipelines/builder`.
    *   **Integration**: Use `phx-hook` for lazy loading the React root.
    *   **Styling**: Use **Tailwind CSS v4** for the canvas container.
    *   **Output**: Generate JSON IR for the backend.

## Iteration 5: Polish & Telemetry
**Goal**: Visibility and Reliability.
*   [ ] **Real-time Metrics**: Wiring Telemetry events to LiveView Dashboard.
*   [ ] **Anomaly Dashboard**: Visualization of the AI signals.
*   [ ] **Load Testing**: Verify back-pressure under high load.

## Iteration 6: Quality Assurance & Handover
**Goal**: Comprehensive Testing and Final Documentation.
*   [ ] **Unit Testing Suite**:
    *   FluxCore: Schema validations and Context logic.
    *   FluxEngine: Broadway topology and Transformation logic.
    *   FluxWeb: LiveView integration tests.
*   [ ] **Integration Testing**: End-to-end flow verification (Source \u2192 Adapter \u2192 Broadway \u2192 Sink).
*   [ ] **Property-Based Testing**: Use `StreamData` to fuzz test the Transformation Engine.
*   [ ] **Technical Documentation**:
    *   API Reference (ExDoc).
    *   Operator Manual (Deployment, Disaster Recovery).
    *   Developer Guide (Adding new Adapters).
