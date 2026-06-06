#!/usr/bin/env bash
#
# Generate CLAUDE.md and AGENTS.md from ai-context/ fragments.
#
#   ai-context/_shared.md      canonical shared conventions (mirrored across repos)
#   ai-context/*.overlay.md    exactly one repo-specific overlay
#       -> CLAUDE.md, AGENTS.md (banner + shared + overlay)
#
# This repo is the source of truth for _shared.md.
#
# Usage:
#   scripts/gen_ai_context.sh           regenerate CLAUDE.md and AGENTS.md
#   scripts/gen_ai_context.sh --check   fail (exit 1) if either file is stale
#
set -euo pipefail

cd "$(dirname "$0")/.."

SHARED="ai-context/_shared.md"
# shellcheck disable=SC2012
OVERLAY="$(ls ai-context/*.overlay.md 2>/dev/null | head -n1 || true)"

[ -f "$SHARED" ]   || { echo "✗ missing $SHARED" >&2; exit 2; }
[ -n "$OVERLAY" ]  || { echo "✗ missing ai-context/*.overlay.md" >&2; exit 2; }

render() {
  cat <<EOF
<!--
  GENERATED FILE — DO NOT EDIT.
  Source: $SHARED + $OVERLAY
  Regenerate: scripts/gen_ai_context.sh
-->

EOF
  cat "$SHARED"
  echo
  cat "$OVERLAY"
}

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

stale=0
for target in CLAUDE.md AGENTS.md; do
  if [ "$CHECK" -eq 1 ]; then
    if ! render | diff -q - "$target" >/dev/null 2>&1; then
      echo "✗ $target is out of date — run scripts/gen_ai_context.sh" >&2
      stale=1
    fi
  else
    render > "$target"
    echo "✓ generated $target (from $OVERLAY)"
  fi
done

if [ "$CHECK" -eq 1 ]; then
  [ "$stale" -eq 0 ] || exit 1
  echo "✓ CLAUDE.md and AGENTS.md are up to date"
fi
