#!/usr/bin/env bash
# Parse bf:bug-hunt arguments and resolve the hunt scope in one call. Emits one JSON object.
#
# Usage: hunt-init.sh [--lenses <id>[,<id>]] [--hunters N] [--repro] [--repo | <path>...]
#   no target  → branch: the current branch vs its merge-base with origin/HEAD (via coherence/scope.sh)
#   <path>...  → paths: every tracked file under those paths, no diff
#   --repo     → repo: every tracked file in the repository, no diff
#
# Output keys: root, mode, base (branch only, else null), files, file_count, diff_file (branch only),
#   lenses (validated override or null), hunters (override or null), hunters_capped, repro,
#   run_dir (created; holds hunters/ and verifiers/), report_path (collision-free), slug.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
set -uo pipefail

LENSES="logic errors concurrency data security contracts"
CAP=6

here=$(cd "$(dirname "$0")" && pwd)
scope="$here/../../coherence/scripts/scope.sh"
die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; exit 1; }
command -v jq >/dev/null || die no_jq "jq is required"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die not_a_git_repo "run inside a git repository"
cd "$root" || exit 1

lenses=""; hunters=""; repro=false; repo=0; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --lenses) lenses="${2-}"; shift 2 ;;
    --lenses=*) lenses="${1#*=}"; shift ;;
    --hunters) hunters="${2-}"; shift 2 ;;
    --hunters=*) hunters="${1#*=}"; shift ;;
    --repro) repro=true; shift ;;
    --repo) repo=1; shift ;;
    --) shift; while [ $# -gt 0 ]; do paths+=("$1"); shift; done ;;
    -*) die unknown_flag "$1" ;;
    *) paths+=("$1"); shift ;;
  esac
done

[ "$repo" = 1 ] && [ "${#paths[@]}" -gt 0 ] && die conflicting_scope "pass --repo or paths, not both"

lenses_json=null
if [ -n "$lenses" ]; then
  picked=""
  for l in $(printf '%s' "$lenses" | tr ',' ' '); do
    case " $LENSES " in *" $l "*) ;; *) die unknown_lens "$l (valid: $LENSES)" ;; esac
    case " $picked " in *" $l "*) ;; *) picked="$picked $l" ;; esac
  done
  lenses_json=$(printf '%s\n' $picked | jq -R . | jq -sc .)
fi

hunters_json=null; capped=false
if [ -n "$hunters" ]; then
  case "$hunters" in ''|*[!0-9]*) die bad_hunters "--hunters takes a positive integer" ;; esac
  [ "$hunters" -ge 1 ] || die bad_hunters "--hunters takes a positive integer"
  if [ "$hunters" -gt "$CAP" ]; then hunters=$CAP; capped=true; fi
  hunters_json=$hunters
fi

base=null; diff_file=null
if [ "$repo" = 1 ]; then
  mode=repo
  files_json=$(git ls-files -z | tr '\0' '\n' | grep -v '^\.bf/' | jq -R . | jq -sc .)
elif [ "${#paths[@]}" -gt 0 ]; then
  mode=paths
  for p in "${paths[@]}"; do [ -e "$p" ] || die no_such_path "$p"; done
  files_json=$(git ls-files -z -- "${paths[@]}" | tr '\0' '\n' | grep -v '^\.bf/' | jq -R . | jq -sc .)
else
  mode=branch
  head=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)
  b=$(git merge-base HEAD "$head" 2>/dev/null) || die no_base "cannot find a merge-base with $head"
  base=$(jq -n --arg b "$b" '$b')
  out=$(bash "$scope" --with-diff branch)
  files_json=$(jq -c '.files' <<< "$out")
  diff_file=$(jq -c '.diff_file // null' <<< "$out")
fi
count=$(jq 'length' <<< "$files_json")
[ "$count" -gt 0 ] || die empty_scope "no files in $mode scope"

stamp=$(date +%Y%m%d-%H%M%S)
case "$mode" in
  branch) label=$(git rev-parse --abbrev-ref HEAD) ;;
  paths) label="${paths[0]}" ;;
  repo) label=repo ;;
esac
label=$(printf '%s' "$label" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//' | cut -c1-40)
slug="${label:-hunt}-$stamp"
out_dir="$root/.bf/bug-hunt"
report="$out_dir/$slug.md"; n=2
while [ -e "$report" ]; do report="$out_dir/$slug-$n.md"; n=$((n + 1)); done
slug=$(basename "$report" .md)
run_dir="$out_dir/runs/$slug"
mkdir -p "$run_dir/hunters" "$run_dir/verifiers" "$run_dir/repro"

jq -nc --arg root "$root" --arg mode "$mode" --argjson base "$base" --argjson files "$files_json" \
  --argjson diff_file "$diff_file" --argjson lenses "$lenses_json" --argjson hunters "$hunters_json" \
  --argjson capped "$capped" --argjson repro "$repro" --arg run_dir "$run_dir" \
  --arg report "$report" --arg slug "$slug" \
  '{root:$root, mode:$mode, base:$base, files:$files, file_count:($files|length), diff_file:$diff_file,
    lenses:$lenses, hunters:$hunters, hunters_capped:$capped, repro:$repro,
    run_dir:$run_dir, report_path:$report, slug:$slug}'
