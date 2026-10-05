#!/usr/bin/env bash
# List the host repository's own review and coding rule files, so a review applies the rules the
# repo's reviewers enforce alongside bf's conventions.
#
# Usage: host-rules.sh
# Output: a JSON array of absolute paths that exist, e.g. ["/repo/AGENTS.md","/repo/CONTRIBUTING.md"];
#         [] when the repo has none.
#         Looks for AGENTS.md, CLAUDE.md, REVIEW.md and CONTRIBUTING.md at the root (any case),
#         .github/CONTRIBUTING.md, and every file under .agents/instructions/.
# Errors: {"error":...,"detail":...} + exit 1 — not_a_git_repo, jq_missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
root=$(git rev-parse --show-toplevel 2>/dev/null) \
  || { printf '{"error":"not_a_git_repo","detail":"run inside the repository under review"}\n'; exit 1; }

# -iname, not a fixed list of spellings: on a case-insensitive filesystem Review.md and REVIEW.md
# would both "exist" and the same file would be listed twice.
{
  find "$root" -maxdepth 1 -type f \( -iname AGENTS.md -o -iname CLAUDE.md -o -iname REVIEW.md -o -iname CONTRIBUTING.md \)
  [ ! -d "$root/.github" ] || find "$root/.github" -maxdepth 1 -type f -iname CONTRIBUTING.md
  [ ! -d "$root/.agents/instructions" ] || find "$root/.agents/instructions" -type f
} | sort | jq -R . | jq -cs .
