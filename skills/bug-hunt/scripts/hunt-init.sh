#!/usr/bin/env bash
# Parse bf:bug-hunt arguments and resolve the hunt scope in one call. Emits one JSON object.
#
# Usage: hunt-init.sh [--lenses <id>[,<id>]] [--hunters N] [--repro] [--pr <n|url> | --repo | <path>...]
#   no target  → branch: the current branch vs its merge-base with origin/HEAD (via coherence/scope.sh)
#   --pr <n>   → pr: the PR's head vs its merge-base with origin/<PR base>. Hunters read the working
#                tree, so HEAD must be the PR's head commit (`gh pr checkout <n>`), else pr_not_checked_out
#   <path>...  → paths: every tracked file under those paths, no diff
#   --repo     → repo: every tracked file in the repository, no diff
#
# Output keys: root, mode, base (branch and pr, else null), pr (pr only, else null), files, file_count,
#   diff_file (branch and pr only),
#   lenses (validated override or null), hunters (override or null), hunters_capped, repro,
#   run_dir (created; holds hunters/, verifiers/ and timing.jsonl, which gets an init row), report_path
#   (collision-free), slug.
# -h, --help prints this text on stdout and exits 0.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
set -uo pipefail

LENSES="logic errors concurrency data security contracts flow"
CAP=6

here=$(cd "$(dirname "$0")" && pwd)
scope="$here/../../coherence/scripts/scope.sh"
die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; exit 1; }
# The header comment is the usage text, so the two cannot drift. Help is checked before the git
# check, so it works outside a repository.
for arg in "$@"; do
  case "$arg" in -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
done
command -v jq >/dev/null || die no_jq "jq is required"
t0=$(jq -n now)
root=$(git rev-parse --show-toplevel 2>/dev/null) || die not_a_git_repo "run inside a git repository"
cd "$root" || exit 1

# Without set -e a failed `shift 2` leaves $1 in place, so a flag with no value would loop forever.
need_value() { [ "$1" -ge 2 ] || die missing_value "$2 needs a value"; }

lenses=""; hunters=""; repro=false; repo=0; pr=""; pr_set=0; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --lenses) need_value $# "$1"; lenses="$2"; shift 2 ;;
    --lenses=*) lenses="${1#*=}"; shift ;;
    --hunters) need_value $# "$1"; hunters="$2"; shift 2 ;;
    --hunters=*) hunters="${1#*=}"; shift ;;
    --repro) repro=true; shift ;;
    --repo) repo=1; shift ;;
    --pr) need_value $# "$1"; pr="$2"; pr_set=1; shift 2 ;;
    --pr=*) pr="${1#*=}"; pr_set=1; shift ;;
    --) shift; while [ $# -gt 0 ]; do paths+=("$1"); shift; done ;;
    -*) die unknown_flag "$1 (run with --help for usage)" ;;
    *) paths+=("$1"); shift ;;
  esac
done

[ "$repo" = 1 ] && [ "${#paths[@]}" -gt 0 ] && die conflicting_scope "pass --repo or paths, not both"
pr_ref=""
if [ "$pr_set" = 1 ]; then
  [ "$repo" = 1 ] || [ "${#paths[@]}" -gt 0 ] && die conflicting_scope "pass --pr, --repo or paths, not more than one"
  # A URL is passed to gh as .../pull/<n>, so gh resolves the PR in the URL's repo, and a copied
  # link to a tab (/files) or a comment (#issuecomment-…) still works.
  case "$pr" in
    */pull/*) pr_ref=$(printf '%s' "$pr" | sed -E 's#(/pull/[0-9]+).*#\1#'); pr="${pr_ref##*/}" ;;
    *) pr="${pr#\#}"; pr_ref=$pr ;;
  esac
  case "$pr" in ''|*[!0-9]*) die bad_pr "--pr takes a PR number or URL" ;; esac
fi

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

base=null; diff_file=null; pr_json=null
if [ "$pr_set" = 1 ]; then
  mode=pr
  command -v gh >/dev/null || die no_gh "gh is required for --pr"
  info=$(gh pr view "$pr_ref" --json headRefOid,headRefName,baseRefName 2>/dev/null) || die pr_not_found "gh pr view $pr_ref failed"
  pr_head=$(jq -r '.headRefOid' <<< "$info")
  pr_branch=$(jq -r '.headRefName' <<< "$info")
  pr_base=$(jq -r '.baseRefName' <<< "$info")
  if [ "$(git rev-parse HEAD)" != "$pr_head" ]; then
    # gh pr checkout does not move a local branch that already differs from the PR head.
    [ "$(git rev-parse --abbrev-ref HEAD)" = "$pr_branch" ] &&
      die pr_not_checked_out "branch $pr_branch is checked out but HEAD differs from PR #$pr's pushed head (${pr_head:0:12}); push or pull so they match, then retry"
    die pr_not_checked_out "HEAD is not the head of PR #$pr (${pr_head:0:12}); run gh pr checkout $pr, then retry"
  fi
  git rev-parse --verify --quiet "origin/$pr_base" >/dev/null ||
    die no_base "origin/$pr_base not found; run git fetch origin $pr_base"
  b=$(git merge-base HEAD "origin/$pr_base" 2>/dev/null) || die no_base "cannot find a merge-base with origin/$pr_base"
  base=$(jq -n --arg b "$b" '$b')
  pr_json=$pr
  out=$(bash "$scope" --with-diff "$b..HEAD")
  files_json=$(jq -c '.files' <<< "$out")
  diff_file=$(jq -c '.diff_file // null' <<< "$out")
elif [ "$repo" = 1 ]; then
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
  pr) label="pr-$pr" ;;
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
jq -nc --argjson a "$t0" '{step: "init", label: "", by: "script", start: $a, end: now}' >> "$run_dir/timing.jsonl" 2>/dev/null || true

jq -nc --arg root "$root" --arg mode "$mode" --argjson base "$base" --argjson pr "$pr_json" --argjson files "$files_json" \
  --argjson diff_file "$diff_file" --argjson lenses "$lenses_json" --argjson hunters "$hunters_json" \
  --argjson capped "$capped" --argjson repro "$repro" --arg run_dir "$run_dir" \
  --arg report "$report" --arg slug "$slug" \
  '{root:$root, mode:$mode, base:$base, pr:$pr, files:$files, file_count:($files|length), diff_file:$diff_file,
    lenses:$lenses, hunters:$hunters, hunters_capped:$capped, repro:$repro,
    run_dir:$run_dir, report_path:$report, slug:$slug}'
