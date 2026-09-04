#!/usr/bin/env bash
# Resolve what to assess for coherence. Emits one JSON object.
#
# Usage: scope.sh [target]
#   target empty      → uncommitted changes; falls back to branch-vs-base when the tree is clean
#   target "branch"   → current branch vs merge-base with origin/HEAD
#   target <sha|range>→ that commit or range
#   target <paths...> → git diff limited to those paths
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || { printf '{"error":"not_a_git_repo"}\n'; exit 0; }
cd "$root" || exit 0
target="${1:-}"

base_ref() {
  local head; head=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)
  git merge-base HEAD "$head" 2>/dev/null || git rev-parse HEAD~1 2>/dev/null
}

if [ -z "$target" ]; then
  mode=working; diff=$(git diff HEAD 2>/dev/null)
  if [ -z "$diff" ]; then mode=branch; diff=$(git diff "$(base_ref)"...HEAD 2>/dev/null); fi
elif [ "$target" = "branch" ]; then
  mode=branch; diff=$(git diff "$(base_ref)"...HEAD 2>/dev/null)
elif git rev-parse --verify --quiet "$target" >/dev/null 2>&1 || [[ "$target" == *..* ]]; then
  mode=range; diff=$(git diff "$target" 2>/dev/null)
else
  mode=paths; diff=$(git diff HEAD -- $target 2>/dev/null)
fi

files=$(printf '%s' "$diff" | sed -n 's#^diff --git a/.* b/##p')
n=$(printf '%s' "$files" | grep -c . || true)
added=$(printf '%s' "$diff" | grep -c '^+[^+]' || true)
removed=$(printf '%s' "$diff" | grep -c '^-[^-]' || true)

json_list() { printf '%s' "$1" | grep . | sed 's/"/\\"/g; s/^/"/; s/$/"/' | paste -sd, -; }
printf '{"root":"%s","mode":"%s","file_count":%s,"added":%s,"removed":%s,"files":[%s]}\n' \
  "$root" "$mode" "${n:-0}" "${added:-0}" "${removed:-0}" "$(json_list "$files")"
