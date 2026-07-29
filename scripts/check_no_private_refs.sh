#!/usr/bin/env bash
# Fails if anything tracked in this repository names the private commercial
# edition (MOS-595).
#
#   scripts/check_no_private_refs.sh
#
# This repo is Apache-2.0 and public. Naming the private repository or its
# internal application identifiers leaks commercial structure that cannot be
# retracted once published — a git history is forever, and so is anyone's clone.
#
# WHAT IS AND IS NOT ALLOWED
#
# Tier and concept language is expected in an open-core repo and is NOT matched
# here: "requires the Pro tier", "the Enterprise build serves Postgres-backed
# rows", "supplied at runtime by the commercial edition", "this is proprietary"
# are all fine and should stay. The public repo is supposed to describe the seams
# it defines and what fills them.
#
# What must not appear is WHERE the implementation lives or WHAT IT IS CALLED:
# the private repository's name, or the OTP application / module identifiers that
# only exist inside it. Name the seam and the contract, never the artifact that
# fills it.
#
# Scans tracked files only (`git ls-files`), so a local scratch file or an
# untracked note cannot fail the build.
#
# COMMIT MESSAGES ARE SCANNED TOO, when a range is given:
#
#   scripts/check_no_private_refs.sh                      # tracked files
#   scripts/check_no_private_refs.sh origin/main..HEAD    # files + those messages
#
# A message is as public as a file and harder to fix — you cannot amend a merged
# commit without rewriting every SHA after it. This was not hypothetical: the
# commit that first removed these references quoted them in its own message to
# show the before/after, and a files-only check passed it.
set -euo pipefail

cd "$(dirname "$0")/.."

# Deliberately narrow. Every pattern here is an identifier that exists only in
# the private edition; none of them can appear innocently.
PATTERN='flux[-_]ee|fluxpro|flux_pro|flux_enterprise|flux_license|flux_control_plane'

# This file necessarily contains the patterns it searches for.
SELF="scripts/check_no_private_refs.sh"

hits="$(git ls-files -z \
  | grep -zZv "^${SELF}$" \
  | xargs -0 grep -IniE "$PATTERN" 2>/dev/null || true)"

# Optional commit-message scan. Skipped silently when no range is passed, so the
# precommit hook stays fast and works on a fresh clone with no upstream ref.
range="${1:-}"
msg_hits=""
if [ -n "$range" ]; then
  msg_hits="$(git log --format='%H %s%n%b' "$range" 2>/dev/null | grep -inE "$PATTERN" || true)"
fi

if [ -n "$hits" ] || [ -n "$msg_hits" ]; then
  cat >&2 <<'EOF'
This repository is public and Apache-2.0. The following name the private
commercial edition or its internal application identifiers:

EOF
  [ -n "$hits" ] && { echo "In tracked files:" >&2; printf '%s\n' "$hits" >&2; echo >&2; }
  [ -n "$msg_hits" ] && {
    echo "In commit messages ($range):" >&2
    printf '%s\n' "$msg_hits" >&2
    echo >&2
    echo "Amend the message. Describing the change without quoting the identifier" >&2
    echo "is always possible — say which file and what it now says instead." >&2
    echo >&2
  }
  cat >&2 <<'EOF'

Rewrite them to describe the SEAM rather than what fills it. For example:

  before:  The Pro build (flux_pro) overrides this with a distributed backend.
  after:   The Pro build overrides this with a distributed backend.

  before:  the real Enterprise provider lives in flux-ee
  after:   the real Enterprise provider is supplied at runtime by the
           commercial edition

Naming a tier is fine. Naming the repository or the OTP application is not.
EOF
  exit 1
fi

echo "No private-edition references in tracked files."
