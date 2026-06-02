# AI Assistant Context — source fragments

The root `CLAUDE.md` and `AGENTS.md` are **generated from this directory**. Do
not edit those files directly (they carry a do-not-edit banner and CI rejects
drift). Edit the fragments here, then regenerate.

## Files

| File | What it is | Edit it? |
|------|------------|----------|
| `_shared.md` | Shared engineering conventions. Source of truth; also used by the commercial edition. | ✅ — but **never** put Pro/EE or commercial-strategy content here; it is public |
| `flux.overlay.md` | Repo-specific block: Community Edition guardrails (Apache 2.0, behaviour-first, "no Pro code here"). | ✅ |
| `../CLAUDE.md`, `../AGENTS.md` | Generated = banner + `_shared.md` + `flux.overlay.md`. | ❌ generated |

## Regenerate

```bash
scripts/gen_ai_context.sh          # rewrite CLAUDE.md + AGENTS.md
scripts/gen_ai_context.sh --check  # CI/precommit: fail if stale
```

`mix precommit` runs the `--check` automatically.

## Editing shared conventions

`_shared.md` holds the conventions shared with the commercial edition, so this
public repo is the source of truth for them. Edit `_shared.md` here, regenerate,
and open your PR — the maintainers handle propagating shared changes to the
private edition. Keep all Pro/EE and commercial-strategy content out of these
fragments; everything here is public.
