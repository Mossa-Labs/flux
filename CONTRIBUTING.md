# Contributing to Flux

Thanks for your interest in contributing! Flux is the **public, Apache-2.0
Community Edition** of the platform. This guide covers how to work in this repo.

## Open-core model

Flux is open-core:

- **`flux` (this repo)** — Community Edition, Apache-2.0. Engine, in-memory
  queue, HTTP/Postgres sinks, team RBAC, the pipeline builder, and the public
  extension points.
- **Flux Pro / Enterprise** — the commercial edition, maintained separately by
  the Flux team. It adds advanced AI, more sinks and queue backends, DLQ,
  alerting, billing, SSO, audit, MFA, and white-label, building on top of this
  repo.

**External contributors work entirely against this repo** — you never need the
commercial edition to build, test, or extend Flux.

### Please don't add Pro/Enterprise code here

This repo is Apache-2.0 and public — once code lands in its git history it
**cannot** be made proprietary again. Commercial features belong in the Pro
edition, not here. If you're unsure whether something is Community or Pro, open
an issue first.

## Extend through behaviours + the registry

Flux is designed so features plug in without the core naming them. Add new
capabilities by implementing a behaviour and registering it — never by
hard-coding a module reference in the engine:

| Extension point | Behaviour | Registry |
|-----------------|-----------|----------|
| Sinks | `Flux.Sink.Adapter` | `Flux.Sink.Registry` |
| Queues | `Flux.Queue.Adapter` | `Flux.Queue.Registry` |
| Pipeline steps | `Flux.Pipeline.Step` | `Flux.Pipeline.StepRegistry` |
| Auth strategies | `Flux.Auth.Strategy` | `Flux.Auth.Registry` |
| License providers | `Flux.License.Provider` | config |

Community adapters self-register at boot in `Flux.Registrations`. See
`docs/developer_guide.md` for worked examples (adding a sink, a queue, a step).

Pro/EE slots are filled by **stub adapters** that return `{:error, :pro_required}`
and surface the upgrade prompt — keep that contract intact.

## Development

```bash
cd app
mix setup          # deps, db create/migrate, assets
mix test           # full suite
mix precommit      # compile (warnings-as-errors) + format + ai-context check + test
```

Run `mix precommit` before opening a PR and fix anything it flags.

## AI assistant context files

`CLAUDE.md` and `AGENTS.md` are **generated** — do not edit them directly. Edit
the fragments in `ai-context/` and run `scripts/gen_ai_context.sh`. The shared
conventions in `ai-context/_shared.md` are also used by the commercial edition;
if you change them, the maintainers handle re-syncing. `mix precommit` and CI
fail if the generated files are stale. See `ai-context/README.md`.

## Pull requests

- Keep PRs focused; include tests.
- PR descriptions: explain *what* and *why* (not a file-by-file list); use
  GitHub-flavored Markdown and Mermaid diagrams where they add clarity.
- By submitting a contribution you agree it is licensed under Apache-2.0.

## Reporting issues

Open a GitHub issue with reproduction steps, expected vs actual behaviour, and
your Flux / Elixir / OTP versions.
