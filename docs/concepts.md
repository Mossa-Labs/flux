# Concepts & Background

New to data pipelines, or to the Erlang/Elixir ecosystem Flux is built on? Start
here. This page explains **what Flux is for**, defines the **vocabulary** used
throughout the rest of the docs, and links each idea to authoritative background
reading so you can go as deep as you like.

If you just want to build a pipeline, jump to the [user guide](user_guide.md).
If you want the system design, read the [architecture overview](architecture_overview.md).

---

## Why Flux, and when to use it

Flux moves data from where it happens to where you need it. You **ingest** events
by pointing webhooks at Flux, **transform** them with a chain of small composable
steps (rename a field, drop records you don't care about, run a bit of custom
Lua), and **deliver** the results to one or more destinations ("sinks") — an HTTP
endpoint, a Postgres table, and more.

This is the classic [ETL/ELT](#further-reading) problem, but Flux is built for the
**event-driven, streaming** end of it: small messages arriving continuously,
processed as they land, rather than giant nightly batch jobs. It runs entirely
**self-hosted on the BEAM** (the Erlang virtual machine), which gives each
pipeline its own lightweight, supervised process that restarts on failure without
taking the rest of the system down.

**Where Flux fits:**

- **Reach for Flux** when you have webhook or event sources, want low-latency
  per-message transforms, and prefer to self-host a single, operationally simple
  service.
- **It is not** a heavyweight DAG orchestrator for long batch workflows (that's
  the niche of tools like Airflow), nor a large catalog of pre-built SaaS
  connectors (Airbyte, Meltano). Flux favors a small, sharp core you extend
  yourself through [behaviours and a registry](#extensibility).

> **Editions.** This repository is the **Community edition** (Apache 2.0).
> Advanced sinks, durable broker queues, clustering/HA, SSO, and other commercial
> capabilities ship as a separate licensed Pro/Enterprise edition. See the
> [open-core model](architecture/open_core.md) for how and why that split works.

---

## Glossary

The terms below are Flux's own vocabulary, in roughly the order data flows through
the system.

| Term | What it means in Flux |
|------|------------------------|
| **Pipeline** | A configured flow: a `source_queue` to read from, an ordered list of `steps` to apply, and the `sink_ids` to deliver results to. Belongs to one organization; has a lifecycle `status` of `active`, `paused`, or `stopped` (new pipelines start `stopped`). |
| **Message** | The unit of data flowing through a pipeline — a `payload` map plus metadata (`id`, `source`, optional `correlation_id` for tracing). |
| **Source queue** | The named queue a pipeline consumes from. Webhook ingestion publishes incoming events here. |
| **Destination queue** | An optional named queue a pipeline can publish its output to, so pipelines can be chained or fanned out. |
| **Step** | One transformation in a pipeline. **Native** steps (Map, Filter, Rename) are compiled Elixir for speed; **Script** steps run user Lua in a sandbox; an **AI** step (anomaly detection) is available in Pro. |
| **Sink** | A delivery destination — HTTP, Postgres, and more in Pro. Each sink has a `type` and a type-specific `config` (secrets are redacted before leaving the system). |
| **Queue adapter** | The pluggable backend that buffers messages. Community ships an in-memory adapter (great for development and single-node); Pro adds durable brokers. |
| **Registry** | The lookup table that maps a string type (`"http"`, `"postgres"`, `"map"`, …) to the module that implements it. How Flux stays extensible without hard-coding adapters into the engine. |
| **IR (intermediate representation)** | The versioned JSON that describes a pipeline's steps. The visual builder reads and writes it; the engine executes it. Decouples the UI from execution and enables round-tripping (edit → save JSON → reload). |
| **Runner** | The per-pipeline [Broadway](#further-reading) process tree that actually executes it: a producer pulls from the queue, processors run the steps, and results are delivered to sinks. |
| **Control plane** | The management/visibility half of Flux (Phoenix LiveView UI, REST API, dashboards) — configuration and monitoring. |
| **Data plane** | The execution half (Broadway runners, the scheduler) — the part that actually moves and transforms data. |
| **Organization / Team** | The multi-tenancy boundary. An organization owns pipelines and sinks; teams and roles govern who can do what. |
| **Scope** | The resolved security context for a request — the user plus their organization and role — checked by the permission API on every protected action. |
| **Dead-letter queue (DLQ)** | Where messages that repeatedly fail processing are parked for inspection instead of being lost. Available with the durable broker queues in Pro. |

---

## Architecture in one paragraph

Flux is split into a **control plane** and a **data plane**. The control plane is a
[Phoenix LiveView](#further-reading) app: it serves the dashboard, the REST API,
and the visual pipeline builder (the only place Flux uses React, via React Flow).
The data plane is built on [Broadway](#further-reading): each active pipeline spawns
its own supervised process tree that consumes from a queue, runs the pipeline's
steps, and delivers to sinks, with [Oban](#further-reading) handling scheduled
work. Both planes run in a single deployable artifact on the BEAM. For the full
picture, see the [architecture overview](architecture_overview.md).

<a id="extensibility"></a>

## How Flux stays extensible

Flux never hard-codes adapters into the engine. Every sink, queue, and pipeline
step is a **behaviour** (an Elixir interface contract) resolved through a
**registry** at runtime — a deliberate use of the
[adapter pattern](#further-reading) and a [registry/service-locator](#further-reading)
lookup. Community adapters register themselves at boot; new ones plug in the same
way without touching the engine. This same seam is what lets the separate Pro
edition register its own adapters at startup. The [developer guide](developer_guide.md)
walks through adding your own sink, queue, or step.

---

<a id="further-reading"></a>

## Further reading

Authoritative background for the concepts and technologies Flux builds on.

### Data pipelines & streaming

- **ETL / ELT** — [Extract, transform, load](https://en.wikipedia.org/wiki/Extract,_transform,_load) · [Extract, load, transform](https://en.wikipedia.org/wiki/Extract,_load,_transform)
- **Stream processing** — [Wikipedia: Stream processing](https://en.wikipedia.org/wiki/Stream_processing)
- **Webhooks** — [Wikipedia: Webhook](https://en.wikipedia.org/wiki/Webhook)
- **Backpressure / demand-driven flow** — [GenStage docs](https://hexdocs.pm/gen_stage/GenStage.html) (the demand model Broadway uses to avoid overwhelming downstream stages)
- **Dead-letter queue** — [Wikipedia: Dead letter queue](https://en.wikipedia.org/wiki/Dead_letter_queue)

### The BEAM runtime

- **BEAM (Erlang VM)** — [Wikipedia: BEAM](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine))
- **Actor model & "let it crash" supervision** — [Wikipedia: Actor model](https://en.wikipedia.org/wiki/Actor_model) · [Elixir: Supervisor](https://hexdocs.pm/elixir/Supervisor.html)
- **Broadway** (data-plane pipelines) — [hexdocs.pm/broadway](https://hexdocs.pm/broadway)
- **Oban** (scheduler / background jobs) — [hexdocs.pm/oban](https://hexdocs.pm/oban)
- **Phoenix LiveView** (control-plane UI) — [hexdocs.pm/phoenix_live_view](https://hexdocs.pm/phoenix_live_view)
- **Lua / Luerl sandbox** (Script steps) — [Wikipedia: Lua](https://en.wikipedia.org/wiki/Lua_(programming_language)) · [Luerl on GitHub](https://github.com/rvirding/luerl)

### Architecture & patterns

- **Open-core model** — [Wikipedia: Open-core model](https://en.wikipedia.org/wiki/Open-core_model)
- **Adapter pattern** — [Wikipedia: Adapter pattern](https://en.wikipedia.org/wiki/Adapter_pattern)
- **Registry / service locator** — [Wikipedia: Service locator pattern](https://en.wikipedia.org/wiki/Service_locator_pattern)
- **Intermediate representation** — [Wikipedia: Intermediate representation](https://en.wikipedia.org/wiki/Intermediate_representation)
- **Control plane / data plane** — [Wikipedia: Control plane](https://en.wikipedia.org/wiki/Control_plane)
- **Multi-tenancy** — [Wikipedia: Multitenancy](https://en.wikipedia.org/wiki/Multitenancy)
- **Role-based access control (RBAC)** — [Wikipedia: Role-based access control](https://en.wikipedia.org/wiki/Role-based_access_control)
