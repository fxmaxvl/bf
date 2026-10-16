#!/usr/bin/env bash
# Find the optional domain override visualize-spec.c4 through the convention tiers. The base spec is always loaded.
#
# Usage:  resolve-spec.sh <project_root|"">   an empty root drops the project tier
# Output: {"base":"/abs/base-spec.c4","override":"/abs/visualize-spec.c4"|null,"override_tier":"project|user|plugin"|null}
# Errors: {"error":...,"detail":...} + exit 1 — usage, jq_missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
[ $# -eq 1 ] || { jq -cn '{error:"usage", detail:"resolve-spec.sh <project_root|\"\">"}'; exit 1; }

# shellcheck source=../../scan-conventions/scripts/convention-tiers.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scan-conventions/scripts/convention-tiers.sh"

root=$1
base=${BF_VIZ_BASE_SPEC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../references" && pwd)/base-spec.c4}

override=; tier=
while IFS=$'\t' read -r t dir; do
  [ -n "$root" ] || [ "$t" != project ] || continue
  if [ -f "$dir/visualize-spec.c4" ]; then override=$dir/visualize-spec.c4; tier=$t; break; fi
done < <(convention_tiers "$root")

jq -cn --arg b "$base" --arg o "$override" --arg t "$tier" \
  '{base:$b, override:(if $o == "" then null else $o end), override_tier:(if $t == "" then null else $t end)}'
