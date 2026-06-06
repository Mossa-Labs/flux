# Migrating from the pre-split monolith

Before Flux 2.0, Flux shipped as a single repository with **every feature enabled
and no tier enforcement**. Flux is now **open core**: this public `flux` repo is
the Apache 2.0 Community edition, and Pro/Enterprise features ship in a separate
licensed distribution.

If you forked or deployed the old monolith, this guide explains exactly what
changed and how to move forward. **If you only ever used Community-tier features,
nothing changes for you** — upgrade and carry on.

## What moved out of the public repo

Adapters and advanced modules that required proprietary integrations were
**removed** from the public repo and now live in the commercial edition. In this
repo their registry slots are filled by **stub adapters** that return
`{:error, :pro_required}` and surface an upgrade prompt.

In practice, on a Community build:

- Any sink or queue **type** other than the Community ones (HTTP and Postgres
  sinks, the in-memory queue) resolves to a stub.
- Advanced analysis modes fall back to basic scoring.

The license feature catalog lives here in `Flux.License.Features` so the editions
agree on entitlement; the implementations it gates do not. Module namespaces were
preserved on the move — nothing was renamed.

## What stayed (the Community edition)

Everything else, fully open under Apache 2.0: the engine, the in-memory queue,
HTTP and Postgres sinks, webhook ingestion, the Map/Filter/Rename/Lua-Script
pipeline steps, team RBAC, the visual builder, the REST API with per-org API
keys, basic AI scoring, and the cluster-aware HA baseline.

## Choose your path

### Path A — You only used Community features

Switch your remote to this repository and pull. Configured `http`/`postgres`
sinks and the `memory` queue work unchanged. Done.

```bash
git remote set-url origin git@github.com:Mossa-Labs/flux.git
git fetch origin && git checkout main && git pull
```

### Path B — You used Pro/EE features and want to keep them

You need the **licensed commercial edition**, which depends on this repo and
registers the real adapters at boot. See the [pricing
page](https://mossa.io/flux/pricing) to get a license, then follow its setup.
Your existing pipeline definitions and Postgres schema are compatible — both
editions run against the same schema.

If you configured a sink or queue type that isn't part of the Community edition,
those keys resolve to the real adapters once the licensed edition registers them;
on a Community build they resolve to stubs and show an upgrade prompt.

### Path C — You forked and modified the monolith's source

- **Community changes** (engine, HTTP/Postgres sinks, steps, builder, RBAC, API):
  rebase onto this repo. The public history was flattened at the split, so rebase
  your changes onto current `main` rather than expecting a shared ancestor.
- **Changes to modules that are now part of the commercial edition**: that source
  is no longer public. Reimplement your changes as your **own** adapter against the
  public behaviours (`Flux.Sink.Adapter`, `Flux.Queue.Adapter`) and register them
  via the registry — you do not need the commercial edition to run your own
  adapter. See [`developer_guide.md`](developer_guide.md) and
  [`architecture/open_core.md`](architecture/open_core.md).

## Writing your own adapter instead of licensing Pro

The split is deliberately **extensible**: a commercial adapter and one you write
yourself are peers — both implement `Flux.Sink.Adapter` and register under a sink
type. If you need an output the Community edition doesn't ship, implement the
behaviour and register it in `Flux.Registrations` (or your own boot hook). Nothing
in the open-core model prevents you from extending Community Flux for your own use.

## Questions

- **Will my pipelines break?** No — pipeline IR and the Postgres schema are
  unchanged across editions.
- **Is my data affected?** No. This is a source-distribution change, not a data
  migration.
- **Where did the strategy/roadmap docs go?** Internal strategy now lives in the
  private repo; public architecture is documented in
  [`architecture/open_core.md`](architecture/open_core.md).
