#!/usr/bin/env bash
# Resolve named conventions through the 3-step lookup in plugin-main.md, first match wins:
# <project_root>/.bf/conventions, then ~/.bf/conventions, then the plugin's conventions/
# (tier order lives in convention-tiers.sh).
#
# Usage: resolve-conventions.sh <name> [<name>...]     e.g. resolve-conventions.sh dev testing git
# Output: one JSON object mapping each name to the winning absolute path, or null when no tier
#         has it — {"dev":"/abs/dev.md","testing":null}
# Errors: {"error":...,"detail":...} + exit 1 — usage, jq_missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
[ $# -gt 0 ] || { jq -cn '{error:"usage", detail:"resolve-conventions.sh <name>..."}'; exit 1; }

# shellcheck source=convention-tiers.sh
source "$(dirname "${BASH_SOURCE[0]}")/convention-tiers.sh"

dirs=()
while IFS=$'\t' read -r _ dir; do dirs+=("$dir"); done < <(convention_tiers)

for name in "$@"; do
  name=${name%.md}
  path=
  for dir in "${dirs[@]}"; do
    if [ -f "$dir/$name.md" ]; then path="$dir/$name.md"; break; fi
  done
  jq -cn --arg n "$name" --arg p "$path" '{($n): (if $p == "" then null else $p end)}'
done | jq -cs 'add'
