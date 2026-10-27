#!/usr/bin/env bash
# Parse bf:essence arguments and resolve every path the run needs. Emits one JSON object.
#
# Usage: essence-init.sh [top N] <path to artifact>
#   Non-"top N" arguments are joined with single spaces, since $ARGUMENTS reaches this unquoted.
#   top N   keep at most N vital directions (default 3); non-negotiables do not count against it
#
# Output keys: root, source, slug, budget, budget_default, lines, out_path (collision-free),
#   ledger_path. out_path lives under <repo>/.bf/essence/, or ~/.bf/essence/ outside a repo.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
#   pr_deferred       the argument names a PR; PR input is not supported yet
#   no_artifact       no path given
#   not_found         path missing or not a regular file
#   empty_artifact    file has no non-blank content
#   already_distilled file is itself a bf:essence output (it starts with the marker line)
#   bad_budget        "top" not followed by a positive integer
set -uo pipefail

MARKER='<!-- bf:essence'
DEFAULT_BUDGET=3

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; exit 1; }
command -v jq >/dev/null || die no_jq "jq is required"

budget=""; src=""
while [ $# -gt 0 ]; do
  case "$1" in
    top|--top)
      case "${2-}" in ''|*[!0-9]*) die bad_budget "top takes a positive integer" ;; esac
      [ "$2" -ge 1 ] || die bad_budget "top takes a positive integer"
      budget=$2; shift 2 ;;
    *) src="${src:+$src }$1"; shift ;;
  esac
done

case "$src" in
  '') die no_artifact "pass the path to a research report, PRD or spec" ;;
  */pull/*|'#'[0-9]*) die pr_deferred "PR input is not supported yet; use /bf:walkthrough for a PR" ;;
esac
case "$src" in *[!0-9]*) ;; *) [ ! -e "$src" ] && die pr_deferred "PR input is not supported yet; use /bf:walkthrough for a PR" ;; esac

[ -f "$src" ] || die not_found "$src"
grep -q '[^[:space:]]' "$src" || die empty_artifact "$src"
head -n 1 "$src" | grep -qF "$MARKER" && die already_distilled "$src is already a bf:essence output; distill its source instead"

budget_default=false
[ -z "$budget" ] && { budget=$DEFAULT_BUDGET; budget_default=true; }

src_abs=$(cd "$(dirname "$src")" && pwd)/$(basename "$src")
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
if [ -n "$root" ]; then out_dir="$root/.bf/essence"; else out_dir="$HOME/.bf/essence"; fi
mkdir -p "$out_dir"

base=$(basename "$src"); base=${base%.*}
slug=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$slug" ] || slug=artifact

stem="$out_dir/$slug-essence"; n=1; cand="$stem"
while [ -e "$cand.md" ]; do n=$((n + 1)); cand="$stem-$n"; done

jq -n --arg root "$root" --arg source "$src_abs" --arg slug "$slug" \
  --argjson budget "$budget" --argjson budget_default "$budget_default" \
  --argjson lines "$(wc -l < "$src" | tr -d ' ')" \
  --arg out_path "$cand.md" --arg ledger_path "$cand.ledger.json" \
  '{root: (if $root == "" then null else $root end), source: $source, slug: $slug,
    budget: $budget, budget_default: $budget_default, lines: $lines,
    out_path: $out_path, ledger_path: $ledger_path}'
