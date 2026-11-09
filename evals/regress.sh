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
      --force) FORCE=1; shift ;;
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
  local lines targets sha base changed n=0
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
  conf_load "$(src_ref "$(src_for pre-push conf)")"
  bl_load "$(src_ref "$(src_for pre-push baseline)")"
  targets=$(prepush_targets <<<"$lines") || return 1
  while read -r sha base; do
    [ -n "$sha" ] || continue
    if [ -n "$(changed_skills "$base" "$sha")" ]; then n=$((n + 1)); fi
  done <<<"$targets"
  echo "Skill gate: $n commit(s) to check, worst case cost $n x \$$REGRESS_MAX_COST_USD."
  while read -r sha base; do
    [ -n "$sha" ] || continue
    gate_at "$sha" "$base" || return 1
  done <<<"$targets"
}

mode_check() {
  local base head
  parse_opts "$@"
  base_fetch
  conf_load "$(src_ref "$(src_for check conf)")"
  bl_load "$(src_ref "$(src_for check baseline)")"
  base=$(printf '%s' "$POS" | head -n 1)
  if [ -z "$base" ]; then base=$(base_mb HEAD) || return 1; fi
  head=$(git rev-parse HEAD </dev/null)
  stale_scan "$head"
  gate_at "$head" "$base"
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

BL_JSON=""

# The only readers and writers of baseline.json are the bl_* functions.
# Loads baseline.json from a source into BL_JSON. An absent file leaves it empty. It must run
# in the main shell.
bl_load() {
  BL_JSON=$(read_at "$1" evals/baseline.json) || BL_JSON=""
  if [ -n "$BL_JSON" ] && ! printf '%s' "$BL_JSON" | jq -e . >/dev/null 2>&1; then
    die "evals/baseline.json at $1 is not valid JSON"
  fi
  return 0
}

bl_field() {
  printf '%s' "$BL_JSON" | jq -r "$1"
}

# True when the new score is below the old score by more than the margin. The small epsilon keeps
# a drop of exactly the margin from reading as a regression.
is_regressed() {
  awk -v old="$1" -v new="$2" -v margin="$REGRESS_MARGIN" 'BEGIN { exit !(new < old - margin - 0.000000001) }'
}

# Passes when the baseline has no entries or was made with the current model, judge model and runs.
bl_settings_match() {
  local model judge runs
  [ -n "$BL_JSON" ] || return 0
  model=$(bl_field .model)
  judge=$(bl_field .judge_model)
  runs=$(bl_field .runs_requested)
  if [ "$model" = "$REGRESS_MODEL" ] && [ "$judge" = "$REGRESS_JUDGE_MODEL" ] && [ "$runs" = "$REGRESS_RUNS" ]; then
    return 0
  fi
  echo "regress: the baseline was made with model $model, judge model $judge, runs $runs." >&2
  echo "regress: the current settings are model $REGRESS_MODEL, judge model $REGRESS_JUDGE_MODEL, runs $REGRESS_RUNS." >&2
  return 1
}

bl_score() {
  printf '%s' "$BL_JSON" | jq -r --arg c "$1" '.cases[$c].score // empty'
}

# Prints ok, regressed, "case changed" or "no baseline" for a case, its tree id and its new score.
bl_verdict() {
  local case=$1 tree=$2 score=$3 old stored
  stored=$(printf '%s' "$BL_JSON" | jq -r --arg c "$case" '.cases[$c].tree // empty' 2>/dev/null) || stored=""
  if [ -z "$stored" ]; then echo "no baseline"; return 0; fi
  if [ "$stored" != "$tree" ]; then echo "case changed"; return 0; fi
  old=$(bl_score "$case")
  if is_regressed "$old" "$score"; then echo regressed; else echo ok; fi
}

# Prints "<case> <stored tree> <current tree or removed>" for each entry whose case dir changed or
# is gone at a commit.
bl_stale() {
  local sha=$1 case stored current
  [ -n "$BL_JSON" ] || return 0
  while IFS=$'\t' read -r case stored; do
    [ -n "$case" ] || continue
    current=$(case_tree "$sha" "$case")
    if [ "$current" != "$stored" ]; then echo "$case $stored ${current:-removed}"; fi
  done < <(printf '%s' "$BL_JSON" | jq -r '.cases | to_entries[] | [.key, .value.tree] | @tsv')
  return 0
}

bl_file() {
  local root
  root=$(repo_root) || return 1
  echo "$root/evals/baseline.json"
}

# Reads rows (case, score, counted runs, requested runs) on stdin and prints them as the JSON
# object of cases, with the tree id of each case dir at the commit.
bl_cases_json() {
  local sha=$1 case score counted rows="" tree
  while IFS=$'\t' read -r case score counted _ || [ -n "$case" ]; do
    [ -n "$case" ] || continue
    tree=$(case_tree "$sha" "$case")
    rows="$rows$case"$'\t'"$score"$'\t'"$counted"$'\t'"$tree"$'\n'
  done
  printf '%s' "$rows" | jq -Rn --arg day "$(date -u +%Y-%m-%d)" '
    [inputs | split("\t") | {key: .[0], value: {score: (.[1] | tonumber), runs_counted: (.[2] | tonumber), tree: .[3], updated_at: $day}}]
    | from_entries'
}

# Writes the whole file from the rows on stdin, with the current settings at the top.
bl_write_full() {
  local sha=$1 file cases version tmp
  file=$(bl_file) || return 1
  cases=$(bl_cases_json "$sha") || return 1
  version=$(read_at "$sha" .claude-plugin/plugin.json | jq -r '.version // "unknown"') || version=unknown
  tmp=$file.tmp
  jq -n --arg model "$REGRESS_MODEL" --arg judge "$REGRESS_JUDGE_MODEL" --argjson runs "$REGRESS_RUNS" \
    --arg version "$version" --arg commit "$(git rev-parse "$sha" </dev/null)" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson cases "$cases" \
    '{model: $model, judge_model: $judge, runs_requested: $runs, plugin_version: $version, commit: $commit, updated_at: $now, cases: $cases}' > "$tmp" || return 1
  mv "$tmp" "$file"
}

# Merges the rows on stdin into the file. It refuses, and leaves the file as it was, when the
# file was made with other settings.
bl_merge() {
  local sha=$1 file cases tmp
  file=$(bl_file) || return 1
  bl_load WT
  if ! bl_settings_match; then
    echo "regress: run --update-baseline without --tag to write the whole file again." >&2
    return 1
  fi
  cases=$(bl_cases_json "$sha") || return 1
  tmp=$file.tmp
  printf '%s' "$BL_JSON" | jq --argjson cases "$cases" '.cases += $cases' > "$tmp" || return 1
  mv "$tmp" "$file"
}

# The first tag of a case, or the first of the preferred tags that the case has.
case_tag() {
  local src=$1 case=$2 tags prefer
  shift 2
  tags=$(case_meta "$src" "$case" tags) || return 1
  for prefer in "$@"; do
    if printf '%s\n' "$tags" | grep -qxF -- "$prefer"; then echo "$prefer"; return 0; fi
  done
  printf '%s\n' "$tags" | head -n 1
}

# Prints the steps that refresh the baseline. It never prints a command that --update-baseline
# would refuse in the current state.
refresh_hint() {
  local flag="" branch=${REGRESS_BASE#*/}
  if [ -n "${1:-}" ]; then flag=" --tag $1"; fi
  if [ "$(git rev-parse HEAD </dev/null)" = "$(git rev-parse "$REGRESS_BASE" </dev/null 2>/dev/null)" ]; then
    echo "  To refresh the baseline: evals/regress.sh --update-baseline$flag"
  else
    echo "  To compare with $REGRESS_BASE now: evals/regress.sh --compare$flag"
    echo "  To refresh after the merge: git switch $branch && git pull --ff-only && evals/regress.sh --update-baseline$flag"
  fi
  echo "  Then commit evals/baseline.json on a new branch and open a PR."
}

# Warns about each baseline entry whose case dir changed or is gone.
stale_scan() {
  local sha=$1 case old new first=""
  while read -r case old new; do
    [ -n "$case" ] || continue
    echo "WARNING: the baseline entry for $case is stale (tree $old, now $new)."
    if [ -z "$first" ]; then first=$(case_tag "$sha" "$case" 2>/dev/null) || first=""; fi
  done < <(bl_stale "$sha")
  if [ -n "$(bl_stale "$sha")" ]; then refresh_hint "$first"; fi
  return 0
}

# Prints the table of rows (case, baseline, new, delta, status) read on stdin.
print_table() {
  printf '%-36s %9s %9s %8s  %s\n' case baseline new delta status
  while IFS=$'\t' read -r case old new delta status; do
    [ -n "$case" ] || continue
    printf '%-36s %9s %9s %8s  %s\n' "$case" "$old" "$new" "$delta" "$status"
  done
}

# The regression check for one commit: coverage, the case list, the run on a worktree at the
# commit, then one verdict per case. The caller has loaded the settings and the baseline.
gate_at() {
  local sha=$1 base=$2 changed kind name covered cases rows out row case score counted tree verdict
  local old delta table="" tag_arr tags="" regressed="" changedcases="" nobase="" first=""
  changed=$(changed_skills "$base" "$sha") || return 1
  if [ -z "$changed" ]; then return 0; fi
  coverage "$sha" <<<"$changed" || return 1
  while read -r kind name; do
    [ -n "$name" ] || continue
    covered=$(cases_with_tag "$sha" "$name") || return 1
    if [ -n "$covered" ]; then tags="$tags $name"; fi
  done <<<"$changed"
  if [ -z "$tags" ]; then return 0; fi
  read -r -a tag_arr <<<"$tags"
  if [ -n "$(git diff --name-only "$base" "$sha" -- evals/baseline.json evals/regress.conf </dev/null)" ]; then
    echo "NOTE: this change edits evals/baseline.json or evals/regress.conf. The gate reads both from $REGRESS_BASE and ignores the edits."
  fi
  if ! bl_settings_match; then
    echo "regress: the baseline does not match the current settings, so scores cannot be compared." >&2
    refresh_hint "${tag_arr[0]}" >&2
    return 1
  fi
  cases=$(selected_cases "$sha" "${tag_arr[@]}") || return 1
  echo "Skills to check:$tags"
  echo "Cases: $(printf '%s' "$cases" | tr '\n' ' ')"
  echo "Cost ceiling: \$$REGRESS_MAX_COST_USD for this run."
  wt_add "$sha" || return 1
  out=$RUN_TMP/run$WT_N
  rows=$(run_and_score "$WT_PATH" "$out" "$sha" "${tag_arr[@]}") || return 1
  while IFS=$'\t' read -r case score counted _ || [ -n "$case" ]; do
    [ -n "$case" ] || continue
    tree=$(case_tree "$sha" "$case")
    verdict=$(bl_verdict "$case" "$tree" "$score")
    old=$(bl_score "$case")
    delta="-"
    if [ -z "$old" ]; then old="-"; fi
    if [ "$old" != "-" ] && [ "$verdict" != "case changed" ]; then
      delta=$(awk -v o="$old" -v n="$score" 'BEGIN { printf "%+.3f", n - o }')
    fi
    table="$table$case"$'\t'"$old"$'\t'"$score"$'\t'"$delta"$'\t'"$verdict"$'\n'
    case "$verdict" in
      regressed) regressed="$regressed $case" ;;
      "case changed") changedcases="$changedcases $case" ;;
      "no baseline") nobase="$nobase $case" ;;
    esac
  done <<<"$rows"
  printf '%s' "$table" | print_table
  echo "Run: $(run_stats "$out")"
  for case in $changedcases; do
    first=$(case_tag "$sha" "$case" "${tag_arr[@]}") || first=""
    echo "WARNING: case $case changed since the baseline (tree $(bl_field ".cases[\"$case\"].tree"), now $(case_tree "$sha" "$case")). Its score is not compared."
    refresh_hint "$first"
  done
  if [ -n "$nobase" ]; then
    echo "NOTE: no baseline for$nobase. The gate passes without a comparison."
    refresh_hint "${tag_arr[0]}"
  fi
  if [ -n "$regressed" ]; then
    echo "regress: dropped more than $REGRESS_MARGIN below the baseline:$regressed. Fix the skill or push with git push --no-verify to skip the gate." >&2
    return 1
  fi
  return 0
}

# Runs the selected cases (all of them with no --tag) on a worktree at HEAD and writes the
# baseline. It refuses on a dirty tree, a stale or off-base HEAD and every fail-closed result.
mode_update_baseline() {
  local head tag_arr=() tag rows
  parse_opts "$@"
  conf_load "$(src_ref "$(src_for update-baseline conf)")"
  if [ -n "$(git status --porcelain -- evals skills </dev/null)" ]; then
    echo "regress: uncommitted changes under evals or skills. Commit or stash them first." >&2
    return 1
  fi
  base_fetch
  if [ -n "$BASE_FETCH_FAILED" ] && [ "$FORCE" -ne 1 ]; then
    echo "regress: could not fetch $REGRESS_BASE. Fix the network or use --force." >&2
    return 1
  fi
  head=$(git rev-parse HEAD </dev/null)
  if [ "$head" != "$(git rev-parse "$REGRESS_BASE" </dev/null 2>/dev/null)" ] && [ "$FORCE" -ne 1 ]; then
    echo "regress: HEAD is not $REGRESS_BASE. Switch to the tip of $REGRESS_BASE or use --force." >&2
    return 1
  fi
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    tag_arr+=("$tag")
  done <<<"$TAGS"
  echo "Cost ceiling: \$$REGRESS_MAX_COST_USD for this run."
  wt_add "$head" || return 1
  rows=$(run_and_score "$WT_PATH" "$RUN_TMP/update" "$head" ${tag_arr[@]+"${tag_arr[@]}"}) || return 1
  bl_load WT
  if [ ${#tag_arr[@]} -gt 0 ] && [ -n "$BL_JSON" ]; then
    printf '%s' "$rows" | bl_merge "$head" || return 1
  else
    printf '%s' "$rows" | bl_write_full "$head" || return 1
  fi
  echo "Wrote evals/baseline.json. Run: $(run_stats "$RUN_TMP/update")"
  echo "Next: commit evals/baseline.json on a new branch and open a PR."
}

main() {
  set -euo pipefail
  command -v jq >/dev/null 2>&1 || die "jq is required. Install it and run again."
  local mode=${1:-}
  case "$mode" in
    --coverage) shift; mode_coverage "$@" ;;
    --pre-push) shift; mode_pre_push "$@" ;;
    --check) shift; mode_check "$@" ;;
    --update-baseline) shift; mode_update_baseline "$@" ;;
    *) usage; exit 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
