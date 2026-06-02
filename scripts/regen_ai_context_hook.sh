#!/usr/bin/env bash
#
# Claude Code PostToolUse hook: regenerate CLAUDE.md / AGENTS.md whenever an
# ai-context/ fragment is edited, so the generated files never go stale.
#
# This is a convenience only — `mix precommit` / CI run gen_ai_context.sh --check
# and remain the source of correctness. The hook just removes the manual regen
# step after editing a fragment.
#
# Wired via .claude/settings.json:
#   "hooks": { "PostToolUse": [ { "matcher": "Edit|Write", "hooks": [
#     { "type": "command", "command": "$CLAUDE_PROJECT_DIR/scripts/regen_ai_context_hook.sh" }
#   ] } ] }
#
# Receives the tool-call payload as JSON on stdin; only regenerates when the
# edited file lives under ai-context/.
#
set -euo pipefail

payload="$(cat)"
file_path="$(printf '%s' "$payload" \
  | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n1)"

case "$file_path" in
  */ai-context/*)
    "$(dirname "$0")/gen_ai_context.sh" >/dev/null 2>&1 || true
    ;;
esac

exit 0
