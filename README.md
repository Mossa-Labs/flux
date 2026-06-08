# Flux

**A fast, self-hosted ETL/ELT platform built on the BEAM.**

Flux is a high-performance data-pipelining engine: ingest from webhooks and
scheduled sources, transform with composable steps (including Lua scripting),
and deliver to your sinks — reliably, on the Erlang VM, with a live visual
builder.

> **This is the Community edition (Apache 2.0).** Pro and Enterprise features
> ship as a **separate licensed distribution** maintained by the Flux team — not
> in this repository. See [open-core model](#open-core) below and the
> [pricing page](https://mossa.io/flux/pricing) for what each tier includes.

---

## What's in the Community edition

Everything you need to run real pipelines in production, free and open source:

| Area | Community (this repo) |
|------|-----------------------|
| **Ingestion** | Webhook (push) sources |
| **Transform** | Map, Filter, Rename, and Lua **Script** steps |
| **Sinks** | HTTP, Postgres |
| **Queue** | In-memory queue adapter |
| **Pipeline builder** | Visual React-Flow canvas on `/pipelines/builder` |
| **REST API** | Full developer API (8 endpoints) with per-organization API keys |
| **Multi-tenancy** | Organizations + team role-based access control (RBAC) |
| **Deployment** | Single-node (horizontal scaling & high availability ship in Pro/Enterprise) |
| **Monitoring** | Real-time metrics dashboard (Phoenix PubSub) |

Pro and Enterprise add advanced capabilities and commercial support, shipped as a
separate licensed edition — see the [pricing page](https://mossa.io/flux/pricing).
None of that source lives here — see the [open-core model](#open-core).

## Quick start

```bash
cd app
mix setup     # deps, db create/migrate, assets
mix phx.server
```

Open <http://localhost:4000>. See [`docs/user_guide.md`](docs/user_guide.md) to
build your first pipeline and [`docs/operator_manual.md`](docs/operator_manual.md)
to run it in production.

## Documentation

- [User guide](docs/user_guide.md) — build and run pipelines
- [Developer guide](docs/developer_guide.md) — extend Flux (add a sink, queue, or step)
- [Architecture overview](docs/architecture_overview.md)
- [Open-core architecture](docs/architecture/open_core.md) — why the two-repo split exists and how it works
- [API reference](docs/api_reference.md)
- [Lua scripting](docs/lua_scripting.md)
- [RBAC](docs/rbac.md)
- [Operator manual](docs/operator_manual.md)

## <a id="open-core"></a>Open-core model

Flux is **open core**. This repository is the Community edition, licensed
Apache 2.0, and contains **no Pro or Enterprise source code**. Pro/EE features
ship in a separate, privately maintained distribution that depends on this repo
and registers its adapters at boot through Flux's behaviour-backed registries.

The split exists for **license integrity**, not just runtime gating: once code is
published under Apache 2.0 it can never be made proprietary again, so commercial
source was never committed here. Community users are unaffected — gated features
surface a clear upgrade prompt, never a crash.

Read [`docs/architecture/open_core.md`](docs/architecture/open_core.md) for the
full design.

## Contributing

External contributors work entirely against this repo. Start with
[`CONTRIBUTING.md`](CONTRIBUTING.md) — Flux extends through **behaviours + a
registry**, so new sinks, queues, and steps plug in without modifying the engine.

## Security

Please report vulnerabilities responsibly — see [`SECURITY.md`](SECURITY.md). Do
not open public issues for security reports.

## License

Apache License 2.0. Copyright © 2026 [Mossa Labs Inc.](https://mossa.io/) —
see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
