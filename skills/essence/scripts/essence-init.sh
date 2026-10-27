#!/usr/bin/env bash
# Parse bf:essence arguments and resolve the paths a run needs. Emits one JSON object.
#
# Usage: essence-init.sh [top N] <path to artifact>
#   The argument line comes from stdin (a quoted heredoc keeps shell metacharacters in the path
#   intact); when positional args are given they are joined with single spaces and used instead.
#   Only a leading "top N" is the budget; the rest of the line, trimmed, is the path verbatim.
#   N is the max number of vital directions (default 3); non-negotiables do not count against it.
#   Creates the output directory: <repo>/.bf/essence/, or ~/.bf/essence/ outside a repo.
#
# Output keys: source (absolute), budget, out_path, ledger_path. out_path never collides with an
#   existing output or ledger.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
#   no_jq             jq is not installed
#   no_artifact       no path given
#   bad_budget        a leading "top" not followed by a positive integer
#   pr_deferred       the path is not an existing file and looks like a PR (#N, N or .../pull/N)
#   not_found         path missing or not a regular file
#   empty_artifact    file has no non-blank content
#   already_distilled file is itself a bf:essence output (its first line starts with MARKER)
set -uo pipefail

# The first line of the SKILL.md output template must start with this, or re-runs on an output
# file will not be refused.
MARKER='<!-- bf:essence'
DEFAULT_BUDGET=3

command -v jq >/dev/null || { printf '{"error":"no_jq","detail":"jq is required"}\n'; exit 1; }
die() { jq -cn --arg e "$1" --arg d "$2" '{error:$e,detail:$d}'; exit 1; }

if [ $# -gt 0 ]; then line="$*"; else line=$(cat); fi
line="${line#"${line%%[![:space:]]*}"}"
line="${line%"${line##*[![:space:]]}"}"

budget=$DEFAULT_BUDGET; src=$line
if [[ $line == top || $line == top[[:space:]]* ]]; then
  [[ $line =~ ^top[[:space:]]+([0-9]+)([[:space:]]+(.*))?$ ]] || die bad_budget "top takes a positive integer"
  [ $((10#${BASH_REMATCH[1]})) -ge 1 ] || die bad_budget "top takes a positive integer"
  budget=$((10#${BASH_REMATCH[1]})); src=${BASH_REMATCH[3]-}
fi

[ -n "$src" ] || die no_artifact "pass the path to a research report, PRD or spec"
if [ ! -e "$src" ] && { [[ $src =~ ^#?[0-9]+$ ]] || [[ $src =~ /pull/[0-9]+ ]]; }; then
  die pr_deferred "PR input is not supported yet; pass a research report, PRD or spec path"
fi
[ -f "$src" ] || die not_found "$src"
grep -q '[^[:space:]]' "$src" || die empty_artifact "$src"
head -n 1 "$src" | grep -qF "$MARKER" && die already_distilled "$src is already a bf:essence output; distill its source instead"

src_abs=$(cd "$(dirname "$src")" && pwd)/$(basename "$src")
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
if [ -n "$root" ]; then out_dir="$root/.bf/essence"; else out_dir="$HOME/.bf/essence"; fi
mkdir -p "$out_dir"

base=$(basename "$src"); base=${base%.*}
slug=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$slug" ] || slug=artifact

stem="$out_dir/$slug-essence"; n=1; cand="$stem"
while [ -e "$cand.md" ] || [ -e "$cand.ledger.json" ]; do n=$((n + 1)); cand="$stem-$n"; done

jq -cn --arg source "$src_abs" --argjson budget "$budget" \
  --arg out_path "$cand.md" --arg ledger_path "$cand.ledger.json" \
  '{source: $source, budget: $budget, out_path: $out_path, ledger_path: $ledger_path}'
