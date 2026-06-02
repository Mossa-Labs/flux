## Repository Scope — Community Edition (public, Apache 2.0)

This is the **public** Flux repository. It ships the **Community Edition only** and is licensed Apache 2.0.

- **Never add Pro or Enterprise code here.** Advanced AI (the `Flux.AI.Detector` anomaly provider), the S3 sink, the RabbitMQ queue, SSO / audit / MFA, billing, and other commercial features ship in the separate **Flux Pro / Enterprise** edition, maintained privately by the Flux team. Anything intended to be license-gated must **never** enter this repo's git history — once published under Apache 2.0 it cannot be made proprietary again.
- **Extend via behaviours + the registry, never by hard-coding adapters:**
  - Sinks implement `Flux.Sink.Adapter` and register through `Flux.Sink.Registry`.
  - Queues implement `Flux.Queue.Adapter` and register through `Flux.Queue.Registry`.
  - Pipeline steps, auth strategies, and license providers follow the same pattern (`Flux.Pipeline.Step`, `Flux.Auth.Strategy`, `Flux.License.Provider`).
- Community adapters self-register at boot in `Flux.Registrations`. Pro/EE slots are filled by **stub adapters** (`Flux.Sink.Adapters.Stub`, `Flux.Queue.Adapters.Stub`) that return `{:error, :pro_required}` and surface an upgrade prompt — they must fail cleanly, never crash at compile or config time.
- External contributors work **only** against this repo. See `CONTRIBUTING.md`.

## AI Context Files

`CLAUDE.md` and `AGENTS.md` in this repo are **generated** — do not edit them directly.

- Source fragments live in `ai-context/`: `_shared.md` (shared engineering conventions) + `flux.overlay.md` (this file, public-only).
- Regenerate with `scripts/gen_ai_context.sh`; CI / `mix precommit` runs `scripts/gen_ai_context.sh --check`.
- `_shared.md` is the source of truth for shared conventions and is also used by the commercial edition; if you change it, the maintainers handle re-syncing. Never put Pro/EE or commercial-strategy content in `_shared.md` — it is public by definition.
