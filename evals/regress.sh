#!/usr/bin/env bash
# Gate bf skill changes against stored eval scores. Maintainer tooling for this repo only.
#
# Usage: regress.sh --pre-push <remote> <url>        git pre-push hook mode, reads ref lines on stdin
#        regress.sh --coverage [<base>]              free check: every added skill has a tagged case
#        regress.sh --check [<base>]                 coverage, then the regression check at HEAD
#        regress.sh --update-baseline [--tag <t>...] [--force]
#                                                    run cases and write evals/baseline.json
#        regress.sh --compare [<ref>] [--tag <t>...] old-vs-new scores, <ref> defaults to REGRESS_BASE
# Output: findings and tables on stdout, reasons on stderr.
# Exit:   0 pass, 1 blocked or error.
#
# Settings: evals/regress.conf holds KEY=value lines. An environment variable of the same name wins.
# REGRESS_BASE comes from the environment or the default origin/main only. A branch must not
# point its own gate at its own baseline.
#
# Source of each input per mode. The hook and --check read the baseline and the conf from
# REGRESS_BASE, so one push cannot lower its own bar.
#   mode             plugin tree   case definitions   baseline.json   regress.conf
#   pre-push         pushed        pushed             base            base
#   coverage         none          head               none            base
#   check            head          head               base            base
#   update-baseline  head          head               wt              wt
#   compare-old      ref           wt                 none            wt
#   compare-new      wt            wt                 none            wt

CONF_KEYS="REGRESS_MARGIN REGRESS_MODEL REGRESS_JUDGE_MODEL REGRESS_RUNS REGRESS_MAX_COST_USD REGRESS_CONCURRENCY"

# Keys set in the environment at load time, so a conf value never replaces them.
ENV_KEYS=""
for _key in $CONF_KEYS; do
  if [ -n "${!_key+x}" ]; then ENV_KEYS="$ENV_KEYS $_key"; fi
done
unset _key
REGRESS_BASE=${REGRESS_BASE:-origin/main}

die() {
  echo "regress: $*" >&2
  exit 1
}

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

conf_default() {
  case "$1" in
    REGRESS_MARGIN) echo 0.34 ;;
    REGRESS_MODEL) echo claude-sonnet-5-5 ;;
    REGRESS_JUDGE_MODEL) echo claude-haiku-5-5 ;;
    REGRESS_RUNS) echo 3 ;;
    REGRESS_MAX_COST_USD) echo 10 ;;
    REGRESS_CONCURRENCY) echo 4 ;;
  esac
}

repo_root() {
  git rev-parse --show-toplevel </dev/null
}

# Reads a file at a commit, or from the working tree when the source is WT.
read_at() {
  local src=$1 path=$2 root
  if [ "$src" = WT ]; then
    root=$(repo_root) || return 1
    cat "$root/$path" 2>/dev/null
  else
    git show "$src:$path" </dev/null 2>/dev/null
  fi
}

# Load order: built-in default, then the conf file at <src>, then the environment.
conf_load() {
  local src=$1 key val conf
  conf=$(read_at "$src" evals/regress.conf) || conf=""
  for key in $CONF_KEYS; do
    case " $ENV_KEYS " in
      *" $key "*) continue ;;
    esac
    val=$(printf '%s\n' "$conf" | sed -n "s/^$key=//p" | tail -n 1 | sed "s/^[\"']//; s/[\"']\$//")
    printf -v "$key" '%s' "${val:-$(conf_default "$key")}"
  done
}

# The one mode-by-input resolver. It prints a source symbol that src_ref turns into a ref.
src_for() {
  local mode=$1 input=$2
  case "$mode:$input" in
    pre-push:plugin | pre-push:cases) echo pushed ;;
    pre-push:baseline | pre-push:conf) echo base ;;
    coverage:plugin | coverage:baseline) echo none ;;
    coverage:cases) echo head ;;
    coverage:conf) echo base ;;
    check:plugin | check:cases) echo head ;;
    check:baseline | check:conf) echo base ;;
    update-baseline:plugin | update-baseline:cases) echo head ;;
    update-baseline:baseline | update-baseline:conf) echo wt ;;
    compare-old:plugin) echo ref ;;
    compare-old:cases | compare-old:conf) echo wt ;;
    compare-old:baseline) echo none ;;
    compare-new:plugin | compare-new:cases | compare-new:conf) echo wt ;;
    compare-new:baseline) echo none ;;
    *) return 1 ;;
  esac
}

# Turns a source symbol into a ref for read_at. The optional second argument is the pushed sha or the compare ref.
src_ref() {
  case "$1" in
    head) echo HEAD ;;
    base) echo "$REGRESS_BASE" ;;
    wt) echo WT ;;
    pushed | ref) echo "${2:-}" ;;
    none) echo "" ;;
    *) return 1 ;;
  esac
}

# Prints the values of one top-level key from YAML text on stdin, one per line. It reads the flow
# form (key: [a, b]) and the block form (- a lines). Any other value exits 3.
yaml_list() {
  awk -v key="$1" -v q="'" '
    function clean(x) {
      gsub(/^[ \t"]+|[ \t"]+$/, "", x)
      gsub("^" q "|" q "$", "", x)
      return x
    }
    function emit(x) {
      x = clean(x)
      if (x ~ /[{}\[\]]/ || x ~ /:[ \t]/) { bad = 1 } else if (x != "") { print x }
    }
    $0 ~ "^" key ":" {
      v = $0
      sub("^" key ":[ \t]*", "", v)
      sub(/[ \t]+#.*$/, "", v)
      sub(/[ \t]+$/, "", v)
      inblock = 0
      if (v ~ /^\[.*\]$/) {
        sub(/^\[/, "", v); sub(/\]$/, "", v)
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) emit(parts[i])
      } else if (v == "") {
        inblock = 1
      } else {
        bad = 1
      }
      next
    }
    inblock && /^[ \t]*-[ \t]+/ { x = $0; sub(/^[ \t]*-[ \t]+/, "", x); emit(x); next }
    inblock && /^[ \t]*$/ { next }
    inblock && /^[ \t]/ { bad = 1; next }
    { inblock = 0 }
    END { if (bad) exit 3 }
  '
}

# Prints the lines between the first two --- lines when the text on stdin starts with ---.
frontmatter() {
  awk 'NR == 1 { if ($0 != "---") exit; next } /^---[ \t]*$/ { exit } { print }'
}

# Lists the case dirs under evals/ that hold a case.yaml or a prompt.md. results/ is never a case.
list_cases() {
  local src=$1 root
  if [ "$src" = WT ]; then
    root=$(repo_root) || return 1
    (cd "$root" && find evals -mindepth 2 -maxdepth 2 \( -name case.yaml -o -name prompt.md \) -print </dev/null)
  else
    git ls-tree -r --name-only "$src" -- evals </dev/null
  fi | sed -En 's#^evals/([^/]+)/(case.yaml|prompt.md)$#\1#p' | grep -v '^results$' | sort -u || true
  return 0
}

# Prints the values of a key (tags or allowed_tools) from both case files, joined with no
# duplicates. A key that is present but unreadable stops the run and names the file.
case_meta() {
  local src=$1 case=$2 key=$3 file text part all=""
  for file in case.yaml prompt.md; do
    text=$(read_at "$src" "evals/$case/$file") || continue
    if [ "$file" = prompt.md ]; then text=$(printf '%s\n' "$text" | frontmatter); fi
    part=$(printf '%s\n' "$text" | yaml_list "$key") || {
      echo "regress: cannot read the $key key in evals/$case/$file" >&2
      return 1
    }
    all=$all$part$'\n'
  done
  printf '%s' "$all" | awk 'NF && !seen[$0]++'
  return 0
}

cases_with_tag() {
  local src=$1 tag=$2 case tags
  while IFS= read -r case; do
    tags=$(case_meta "$src" "$case" tags) || return 1
    if printf '%s\n' "$tags" | grep -qxF -- "$tag"; then echo "$case"; fi
  done < <(list_cases "$src")
  return 0
}

# The git tree id of a case dir at a commit. It is empty when the dir is absent there.
case_tree() {
  git rev-parse --verify -q "$1:evals/$2" </dev/null || true
}

# Maps a diff to skill names. Output lines are "added <name>" or "edited <name>". A skill is a
# top-level dir of skills/ with a SKILL.md at the head. The head is a commit or WT, and WT also
# counts untracked files.
changed_skills() {
  local base=$1 head=$2 root names name kind
  root=$(repo_root) || return 1
  if [ "$head" = WT ]; then
    names=$({ git diff --name-only --no-renames "$base" -- skills </dev/null
      git ls-files --others --exclude-standard -- skills </dev/null; }) || return 1
  else
    names=$(git diff --name-only --no-renames "$base" "$head" -- skills </dev/null) || return 1
  fi
  names=$(printf '%s\n' "$names" | sed -En 's#^skills/([^/]+)/.+#\1#p' | sort -u)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$head" = WT ]; then
      [ -f "$root/skills/$name/SKILL.md" ] || continue
    else
      git cat-file -e "$head:skills/$name/SKILL.md" </dev/null 2>/dev/null || continue
    fi
    kind=edited
    git cat-file -e "$base:skills/$name/SKILL.md" </dev/null 2>/dev/null || kind=added
    echo "$kind $name"
  done <<<"$names"
  return 0
}

# Fetches REGRESS_BASE once per run. A failed fetch warns with the age of the local copy and
# sets BASE_FETCH_FAILED. Nothing else in this script fetches.
base_fetch() {
  local remote branch age
  if [ -n "${BASE_FETCHED:-}" ]; then return 0; fi
  BASE_FETCHED=1
  BASE_FETCH_FAILED=
  case "$REGRESS_BASE" in
    */*) ;;
    *) return 0 ;;
  esac
  remote=${REGRESS_BASE%%/*}
  branch=${REGRESS_BASE#*/}
  if ! git fetch --quiet "$remote" "$branch" </dev/null 2>/dev/null; then
    # shellcheck disable=SC2034
    BASE_FETCH_FAILED=1
    age=$(git log -1 --format=%cr "$REGRESS_BASE" </dev/null 2>/dev/null) || age="an unknown time ago"
    echo "WARNING: could not fetch $REGRESS_BASE, using a copy from $age" >&2
  fi
  return 0
}

# The merge-base of a commit and REGRESS_BASE. This is the one place that fetches before it
# reads the base. It fails with the reason when no merge-base exists.
base_mb() {
  local head=$1 mb
  base_fetch
  if ! mb=$(git merge-base "$head" "$REGRESS_BASE" </dev/null 2>/dev/null) || [ -z "$mb" ]; then
    echo "regress: no merge-base between $head and $REGRESS_BASE. Fix the ref or push with git push --no-verify." >&2
    return 1
  fi
  echo "$mb"
}

# Reads "added <name>" and "edited <name>" lines on stdin. An added skill needs a case tagged
# with its name. An edited skill without one only warns.
coverage() {
  local src=$1 kind name covered blocked=0
  while read -r kind name; do
    [ -n "$name" ] || continue
    covered=$(cases_with_tag "$src" "$name") || return 1
    if [ -n "$covered" ]; then continue; fi
    if [ "$kind" = added ]; then
      echo "regress: skill $name is new and has no eval case. Add a case under evals/ tagged $name." >&2
      blocked=1
    else
      echo "WARNING: skill $name has no eval case tagged $name."
    fi
  done
  [ "$blocked" -eq 0 ]
}

# Sets TAGS (one per line), FORCE and POS (positional arguments, one per line).
parse_opts() {
  TAGS=""
  FORCE=0
  POS=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tag)
        [ $# -ge 2 ] || die "--tag needs a value"
        TAGS="$TAGS$2"$'\n'
        shift 2
        ;;
      --force) # shellcheck disable=SC2034
        FORCE=1; shift ;;
      -*) die "unknown option $1" ;;
      *) POS="$POS$1"$'\n'; shift ;;
    esac
  done
}

mode_coverage() {
  local base
  parse_opts "$@"
  base=$(printf '%s' "$POS" | head -n 1)
  if [ -z "$base" ]; then base=$(base_mb HEAD) || return 1; fi
  changed_skills "$base" HEAD | coverage HEAD
}

# Reads pre-push ref lines on stdin and prints "<local sha> <base sha>" for each distinct local
# sha. A delete is skipped. A new branch, or a remote sha this clone does not have, diffs from
# the merge-base with REGRESS_BASE. Any other update diffs from the remote sha.
prepush_targets() {
  local lsha rsha base
  while read -r _ lsha _ rsha; do
    [ -n "$lsha" ] || continue
    if [ -z "${lsha//0/}" ]; then continue; fi
    if [ -n "${rsha//0/}" ] && git cat-file -e "$rsha^{commit}" </dev/null 2>/dev/null; then
      base=$rsha
    else
      base=$(git merge-base "$lsha" "$REGRESS_BASE" </dev/null 2>/dev/null) || base=$(base_mb "$lsha") || return 1
    fi
    echo "$lsha $base"
  done | awk '!seen[$1]++'
}

mode_pre_push() {
  local lines targets sha base changed fail=0
  lines=$(cat)
  exec </dev/null
  targets=$(prepush_targets <<<"$lines") || return 1
  changed=""
  while read -r sha base; do
    [ -n "$sha" ] || continue
    changed="$changed$(changed_skills "$base" "$sha")"
  done <<<"$targets"
  if [ -z "$changed" ]; then return 0; fi
  base_fetch
  targets=$(prepush_targets <<<"$lines") || return 1
  while read -r sha base; do
    [ -n "$sha" ] || continue
    changed=$(changed_skills "$base" "$sha") || return 1
    if [ -z "$changed" ]; then continue; fi
    coverage "$sha" <<<"$changed" || fail=1
  done <<<"$targets"
  [ "$fail" -eq 0 ]
}

WT_DIRS=""
WT_N=0
RUN_TMP=""

# Removes every worktree and the temp dir. It is safe to call more than once.
wt_cleanup() {
  local dir
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    git worktree remove --force "$dir" </dev/null >/dev/null 2>&1 || true
  done <<<"$WT_DIRS"
  git worktree prune </dev/null >/dev/null 2>&1 || true
  if [ -n "$RUN_TMP" ]; then rm -rf "$RUN_TMP"; fi
  WT_DIRS=""
  RUN_TMP=""
}

# Creates the temp dir and the one trap that cleans up. It must run in the main shell, so no
# caller may capture wt_add or wt_init with $(...).
wt_init() {
  if [ -n "$RUN_TMP" ]; then return 0; fi
  RUN_TMP=$(cd "$(mktemp -d)" && pwd -P) || return 1
  trap wt_cleanup EXIT
  trap 'wt_cleanup; exit 130' INT
  trap 'wt_cleanup; exit 143' TERM
}

# Adds a detached worktree at a commit and sets WT_PATH. Git sets the three unset variables
# for a hook, and they point nested git calls at the wrong tree.
wt_add() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
  wt_init || return 1
  WT_N=$((WT_N + 1))
  WT_PATH=$RUN_TMP/wt$WT_N
  if ! git worktree add --detach --quiet "$WT_PATH" "$1" </dev/null >/dev/null 2>&1; then
    echo "regress: cannot create a worktree at $1" >&2
    return 1
  fi
  WT_DIRS="$WT_DIRS$WT_PATH"$'\n'
}

# Prints the reason and the escape hatch, then fails.
fail_closed() {
  echo "regress: $1. The gate fails closed. Push with git push --no-verify to skip it." >&2
  return 1
}

# The cases a run selects: those with any of the tags, or every case when no tag is given.
selected_cases() {
  local src=$1 tag
  shift
  if [ $# -eq 0 ]; then
    list_cases "$src"
  else
    for tag in "$@"; do cases_with_tag "$src" "$tag"; done | awk 'NF && !seen[$0]++'
  fi
}

# The tools of the given cases that the CLI gates behind --allow-tools.
gated_tools() {
  local src=$1 cases=$2 case
  while IFS= read -r case; do
    [ -n "$case" ] || continue
    case_meta "$src" "$case" allowed_tools || return 1
  done <<<"$cases" | awk 'NF && !seen[$0]++' | grep -E '^(Bash|Write|Edit|WebFetch|mcp__.*)(\(.*\))?$' || true
}

# Runs claude plugin eval on a plugin dir for the cases selected by the tags and prints one row
# per case: name, mean score, counted runs, requested runs. The score is the mean over counted
# runs. An errored run or a run that skipped its paid graders does not count. Any partial,
# failed or short result fails closed. The target comes first and the two variadic flags last,
# so a variadic flag cannot consume the target.
run_and_score() {
  local plugin=$1 out=$2 src=$3 cases tools tool rc=0 result case row name counted rows=""
  shift 3
  cases=$(selected_cases "$src" "$@") || return 1
  [ -n "$cases" ] || { fail_closed "no eval case matches the selected tags"; return 1; }
  tools=$(gated_tools "$src" "$cases") || return 1
  mkdir -p "$out"
  result=$out/result.json
  local args=(plugin eval "$plugin" --ablation none --threshold 0
    --model "$REGRESS_MODEL" --judge-model "$REGRESS_JUDGE_MODEL" --runs "$REGRESS_RUNS"
    --max-cost-usd "$REGRESS_MAX_COST_USD" -j "$REGRESS_CONCURRENCY" --scaffold --trust-plugin
    --no-publish --json "$result" --output-dir "$out/out" --report "$out/report.html")
  if [ $# -gt 0 ]; then args+=(--tag "$@"); fi
  if [ -n "$tools" ]; then
    args+=(--allow-tools)
    while IFS= read -r tool; do args+=("$tool"); done <<<"$tools"
  fi
  claude "${args[@]}" </dev/null >"$out/claude.log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -n 5 "$out/claude.log" >&2
    if [ "$rc" -eq 2 ]; then fail_closed "claude plugin eval ended with a partial run"; else fail_closed "claude plugin eval exited with status $rc"; fi
    return 1
  fi
  if ! jq -e . "$result" >/dev/null 2>&1; then
    fail_closed "claude plugin eval wrote no readable result"
    return 1
  fi
  if [ "$(jq -r '.partial // false' "$result")" = true ]; then
    fail_closed "the run was partial: $(jq -r '.partialReason // "no reason given"' "$result")"
    return 1
  fi
  while IFS= read -r case; do
    [ -n "$case" ] || continue
    row=$(jq -r --arg n "$case" --argjson want "$REGRESS_RUNS" '
      (.cases[] | select(.name == $n)) as $c
      | [$c.arms.with[] | select(.error == null and ((.skippedPaidGraders // false) | not)) | .score] as $s
      | [$n, (if ($s | length) > 0 then (($s | add) / ($s | length) * 1000 | round / 1000) else "" end), ($s | length), $want]
      | @tsv' "$result")
    if [ -z "$row" ]; then
      fail_closed "case $case is missing from the result"
      return 1
    fi
    IFS=$'\t' read -r name _ counted _ <<<"$row"
    if [ "$counted" -lt "$REGRESS_RUNS" ]; then
      fail_closed "case $name has $counted counted runs of $REGRESS_RUNS"
      return 1
    fi
    rows="$rows$row"$'\n'
  done <<<"$cases"
  printf '%s' "$rows"
}

# Prints the cost and the duration of a finished run.
run_stats() {
  jq -r '"cost $\(.costUsd // 0) in \(.durationSeconds // 0) s"' "$1/result.json"
}

main() {
  set -euo pipefail
  command -v jq >/dev/null 2>&1 || die "jq is required. Install it and run again."
  local mode=${1:-}
  case "$mode" in
    --coverage) shift; mode_coverage "$@" ;;
    --pre-push) shift; mode_pre_push "$@" ;;
    *) usage; exit 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
