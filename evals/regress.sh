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
# Settings: built-in defaults in this script, then the KEY=value overrides in evals/regress.conf,
# then an environment variable of the same name.
# REGRESS_BASE comes from the environment or the default origin/main only. A branch must not
# point its own gate at its own baseline.
#
# Source of each input per mode. The hook and --check read the baseline and the conf from
# REGRESS_BASE, so one push cannot lower its own bar.
#   mode             plugin tree   case definitions   baseline.json   regress.conf
#   pre-push         pushed        pushed             base            base
#   coverage         none          head               none            none
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

# Prints the last value of a key in KEY=value text, without surrounding quotes.
conf_value() {
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -n 1 | sed "s/^[\"']//; s/[\"']\$//"
}

# Prints the built-in default of a key. This is the only place the defaults live.
# evals/regress.conf holds overrides only.
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

# Load order: the built-in defaults, then the overrides in evals/regress.conf at <src>, then the
# environment. The conf is read from <src> only, never from the working tree of a hook run.
conf_load() {
  local src=$1 key val conf
  conf=$(read_at "$src" evals/regress.conf) || conf=""
  for key in $CONF_KEYS; do
    case " $ENV_KEYS " in
      *" $key "*) continue ;;
    esac
    val=$(conf_value "$conf" "$key")
    if [ -z "$val" ]; then val=$(conf_default "$key"); fi
    printf -v "$key" '%s' "$val"
  done
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

# Fetches REGRESS_BASE once per run in the main shell. A fetch inside $(...) does not set
# BASE_FETCHED in the main shell, so a later call fetches again. A failed fetch warns with the age
# of the local copy and sets BASE_FETCH_FAILED.
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

# The merge-base of a commit and REGRESS_BASE, read after one fetch of the base. It fails with
# the reason when no merge-base exists.
base_mb() {
  local head=$1 mb
  base_fetch
  if ! mb=$(git merge-base "$head" "$REGRESS_BASE" </dev/null 2>/dev/null) || [ -z "$mb" ]; then
    echo "regress: no merge-base between $head and $REGRESS_BASE. Fix the ref or push with git push --no-verify." >&2
    return 1
  fi
  echo "$mb"
}

# Reads "added <name>" and "edited <name>" lines on stdin and prints "<kind> <name> tagged" or
# "<kind> <name> untagged", by whether a case at <src> carries the skill name as a tag.
tag_status() {
  local src=$1 kind name covered
  while read -r kind name; do
    [ -n "$name" ] || continue
    covered=$(cases_with_tag "$src" "$name") || return 1
    if [ -n "$covered" ]; then echo "$kind $name tagged"; else echo "$kind $name untagged"; fi
  done
}

# Reads tag_status lines on stdin and prints the tagged names, each with a leading space.
tagged_names() {
  awk '$3 == "tagged" { printf " %s", $2 }'
}

# Reads tag_status lines on stdin. An added skill needs a case tagged with its name. An edited
# skill without one only warns.
coverage() {
  local kind name status blocked=0
  while read -r kind name status; do
    [ -n "$name" ] || continue
    if [ "$status" = tagged ]; then continue; fi
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
  changed_skills "$base" HEAD | tag_status HEAD | coverage
}

# The commit to diff from for a commit: the merge-base of the commit and <ref>, so a skill that
# only <ref> changed never counts as a change of the commit. With a <floor> commit that lies between
# the merge-base and the commit, the floor is the base, because the earlier part was pushed
# already. A floor outside that range, such as a rebased remote sha, is ignored. A missing
# merge-base with REGRESS_BASE fetches once, then fails with the reason.
diff_base() {
  local head=$1 ref=$2 floor=${3:-} mb
  if ! mb=$(git merge-base "$head" "$ref" </dev/null 2>/dev/null) || [ -z "$mb" ]; then
    if [ "$ref" = "$REGRESS_BASE" ]; then
      mb=$(base_mb "$head") || return 1
    else
      echo "regress: no merge-base between $head and $ref." >&2
      return 1
    fi
  fi
  if [ -n "${floor//0/}" ] && git cat-file -e "$floor^{commit}" </dev/null 2>/dev/null \
    && git merge-base --is-ancestor "$mb" "$floor" </dev/null 2>/dev/null \
    && git merge-base --is-ancestor "$floor" "$head" </dev/null 2>/dev/null; then
    git rev-parse "$floor^{commit}" </dev/null
  else
    echo "$mb"
  fi
}

# Reads pre-push ref lines on stdin and prints "<commit> <base>" for each distinct commit. A tag
# sha is peeled to its commit, so an annotated tag and its commit are one target. A delete is
# skipped. The base comes from diff_base. When two lines give one commit, the earlier base wins, so
# the order of the lines does not change the diff.
prepush_targets() {
  local lsha rsha commit base i n=0 found
  local shas=() bases=()
  while read -r _ lsha _ rsha; do
    [ -n "$lsha" ] || continue
    if [ -z "${lsha//0/}" ]; then continue; fi
    commit=$(git rev-parse --verify -q "$lsha^{commit}" </dev/null 2>/dev/null) || continue
    base=$(diff_base "$commit" "$REGRESS_BASE" "$rsha") || return 1
    found=-1
    for ((i = 0; i < n; i++)); do
      if [ "${shas[i]}" = "$commit" ]; then found=$i; fi
    done
    if [ "$found" -lt 0 ]; then
      shas[n]=$commit
      bases[n]=$base
      n=$((n + 1))
    elif git merge-base --is-ancestor "$base" "${bases[found]}" </dev/null 2>/dev/null; then
      bases[found]=$base
    fi
  done
  for ((i = 0; i < n; i++)); do echo "${shas[i]} ${bases[i]}"; done
  return 0
}

# Fetches the base, then loads the settings and the baseline from REGRESS_BASE for gate_at and
# the readers it calls.
gate_load() {
  base_fetch
  conf_load "$REGRESS_BASE"
  bl_load "$REGRESS_BASE"
  GATE_LOADED=1
}

# Fills PLAN_SHAS, PLAN_BASES and PLAN_CHANGES from pre-push ref lines, one entry for each
# distinct local sha that adds or edits a skill.
prepush_plan() {
  local targets sha base changed
  PLAN_SHAS=()
  PLAN_BASES=()
  PLAN_CHANGES=()
  targets=$(prepush_targets <<<"$1") || return 1
  while read -r sha base; do
    [ -n "$sha" ] || continue
    changed=$(changed_skills "$base" "$sha") || return 1
    [ -n "$changed" ] || continue
    PLAN_SHAS+=("$sha")
    PLAN_BASES+=("$base")
    PLAN_CHANGES+=("$changed")
  done <<<"$targets"
}

mode_pre_push() {
  local lines i n
  local statuses=()
  lines=$(cat)
  exec </dev/null
  prepush_plan "$lines" || return 1
  if [ ${#PLAN_SHAS[@]} -eq 0 ]; then return 0; fi
  # The first plan uses the local base, so a push that changes no skill uses the network only
  # when no local merge-base exists. The fetch moves the base, so the plan is made again.
  gate_load
  prepush_plan "$lines" || return 1
  n=${#PLAN_SHAS[@]}
  if [ "$n" -eq 0 ]; then return 0; fi
  echo "Skill gate: $n commit(s) to check, worst case cost $n x \$$REGRESS_MAX_COST_USD."
  # Every free coverage check runs before the first paid run, so a later ref cannot fail coverage after an earlier ref has spent money.
  for ((i = 0; i < n; i++)); do
    statuses[i]=$(tag_status "${PLAN_SHAS[i]}" <<<"${PLAN_CHANGES[i]}") || return 1
    coverage <<<"${statuses[i]}" || return 1
  done
  for ((i = 0; i < n; i++)); do
    gate_at "${PLAN_SHAS[i]}" "${PLAN_BASES[i]}" "${statuses[i]}" || return 1
  done
}

mode_check() {
  local base head changed statuses
  parse_opts "$@"
  gate_load
  base=$(printf '%s' "$POS" | head -n 1)
  if [ -z "$base" ]; then base=$(base_mb HEAD) || return 1; fi
  head=$(git rev-parse HEAD </dev/null)
  stale_scan "$head"
  changed=$(changed_skills "$base" "$head") || return 1
  statuses=$(tag_status "$head" <<<"$changed") || return 1
  coverage <<<"$statuses" || return 1
  gate_at "$head" "$base" "$statuses"
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
  local tmp
  if [ -n "$RUN_TMP" ]; then return 0; fi
  tmp=$(mktemp -d) || { echo "regress: cannot create a temp dir" >&2; return 1; }
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "regress: cannot create a temp dir" >&2
    return 1
  fi
  RUN_TMP=$(cd "$tmp" && pwd -P) || return 1
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
# failed or short result fails closed. A case with no counted run has the score "-" and fails
# the short-run check, so an empty field never reaches a reader that splits on tabs. The target
# comes first and the two variadic flags last, so a variadic flag cannot consume the target.
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
      | [$n, (if ($s | length) > 0 then (($s | add) / ($s | length) * 1000 | round / 1000) else "-" end), ($s | length), $want]
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

# True when a baseline file was loaded.
bl_present() {
  [ -n "$BL_JSON" ]
}

# The stored tree id of a case, or nothing.
bl_tree() {
  printf '%s' "$BL_JSON" | jq -r --arg c "$1" '.cases[$c].tree // empty' 2>/dev/null || true
}

bl_score() {
  printf '%s' "$BL_JSON" | jq -r --arg c "$1" '.cases[$c].score // empty'
}

# Prints ok, regressed, "case changed" or "no baseline" for a case, its tree id and its new score.
bl_verdict() {
  local case=$1 tree=$2 score=$3 old stored
  stored=$(bl_tree "$case")
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

# Passes when a merge into the loaded baseline is allowed: the file is absent or was made with
# the current settings.
bl_merge_check() {
  if ! bl_settings_match; then
    echo "regress: run --update-baseline without --tag to write the whole file again." >&2
    return 1
  fi
}

# Merges the rows on stdin into the working-tree file that bl_load WT put in BL_JSON. It refuses,
# and leaves the file as it was, when the file was made with other settings.
bl_merge() {
  local sha=$1 file cases tmp
  file=$(bl_file) || return 1
  bl_merge_check || return 1
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
  local flag="" upd_flag branch=${REGRESS_BASE#*/}
  if [ -n "${1:-}" ]; then flag=" --tag $1"; fi
  # bl_merge_check refuses a tagged update when the settings differ, so only a full rewrite works then.
  upd_flag=$flag
  bl_settings_match 2>/dev/null || upd_flag=""
  if [ "$(git rev-parse HEAD </dev/null)" = "$(git rev-parse "$REGRESS_BASE" </dev/null 2>/dev/null)" ]; then
    echo "  To refresh the baseline: evals/regress.sh --update-baseline$upd_flag"
  else
    echo "  To compare with $REGRESS_BASE now: evals/regress.sh --compare$flag"
    echo "  To refresh after the merge: git switch $branch && git pull --ff-only && evals/regress.sh --update-baseline$upd_flag"
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

# Prints the signed change from an old score to a new one, to three decimals.
score_delta() {
  awk -v o="$1" -v n="$2" 'BEGIN { printf "%+.3f", n - o }'
}

# Prints the table of rows (case, baseline, new, delta, status) read on stdin.
print_table() {
  printf '%-36s %9s %9s %8s  %s\n' case "${1:-baseline}" new delta status
  while IFS=$'\t' read -r case old new delta status; do
    [ -n "$case" ] || continue
    printf '%-36s %9s %9s %8s  %s\n' "$case" "$old" "$new" "$delta" "$status"
  done
}

# The regression check for one commit: the case list, the run on a worktree at the commit, then
# one verdict per case. The caller passes the tag_status lines of the changed skills, the same
# lines it gave to coverage. It reads the settings and the baseline that gate_load set.
gate_at() {
  local sha=$1 base=$2 statuses=$3 cases rows out row case score counted tree verdict
  local old delta table="" tag_arr tags="" regressed="" changedcases="" nobase="" first=""
  [ -n "${GATE_LOADED:-}" ] || die "gate_at ran before gate_load"
  if [ -z "$statuses" ]; then return 0; fi
  if grep -q '^added .* untagged$' <<<"$statuses"; then die "gate_at ran with an uncovered added skill"; fi
  tags=$(tagged_names <<<"$statuses")
  if [ -z "$tags" ]; then return 0; fi
  read -r -a tag_arr <<<"$tags"
  if [ -n "$(git diff --name-only "$(diff_base "$sha" "$REGRESS_BASE")" "$sha" -- evals/baseline.json evals/regress.conf </dev/null)" ]; then
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
      delta=$(score_delta "$old" "$score")
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
    echo "WARNING: case $case changed since the baseline (tree $(bl_tree "$case"), now $(case_tree "$sha" "$case")). Its score is not compared."
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
  conf_load WT
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
  if [ ${#tag_arr[@]} -gt 0 ]; then
    # A merge into a file made with other settings is refused, so refuse before the paid run.
    bl_load WT
    bl_merge_check || return 1
  fi
  echo "Cost ceiling: \$$REGRESS_MAX_COST_USD for this run."
  wt_add "$head" || return 1
  rows=$(run_and_score "$WT_PATH" "$RUN_TMP/update" "$head" ${tag_arr[@]+"${tag_arr[@]}"}) || return 1
  if [ ${#tag_arr[@]} -gt 0 ] && bl_present; then
    printf '%s' "$rows" | bl_merge "$head" || return 1
  else
    printf '%s' "$rows" | bl_write_full "$head" || return 1
  fi
  echo "Wrote evals/baseline.json. Run: $(run_stats "$RUN_TMP/update")"
  echo "Next: commit evals/baseline.json on a new branch and open a PR."
}

# The score of a case in a block of rows (case, score, counted, requested), or nothing.
row_score() {
  printf '%s\n' "$1" | awk -F'\t' -v n="$2" '$1 == n { print $2 }'
}

# Prints the old-vs-new table for two blocks of rows and returns 1 when any case dropped by more
# than the margin. A case on one side only is labeled and never marked.
compare_table() {
  local old=$1 new=$2 case o n delta status marked=0 table="" names
  names=$({ printf '%s\n' "$old"; printf '%s\n' "$new"; } | awk -F'\t' 'NF && !seen[$1]++ { print $1 }')
  while IFS= read -r case; do
    [ -n "$case" ] || continue
    o=$(row_score "$old" "$case")
    n=$(row_score "$new" "$case")
    delta="-"
    if [ -z "$o" ]; then
      status="new case"; o="-"
    elif [ -z "$n" ]; then
      status="removed case"; n="-"
    else
      delta=$(score_delta "$o" "$n")
      if is_regressed "$o" "$n"; then status=regressed; marked=1; else status=ok; fi
    fi
    table="$table$case"$'\t'"$o"$'\t'"$n"$'\t'"$delta"$'\t'"$status"$'\n'
  done <<<"$names"
  printf '%s' "$table" | print_table old
  [ "$marked" -eq 0 ]
}

# Runs the same cases against the plugin at <ref> and against the working tree, and compares the
# scores case by case. The old side uses the working-tree evals dir, so both sides share one set
# of case definitions.
mode_compare() {
  local ref root base changed kind name status statuses tags="" tag_arr=() old_rows new_rows
  parse_opts "$@"
  conf_load WT
  base_fetch
  ref=$(printf '%s' "$POS" | head -n 1)
  if [ -z "$ref" ]; then ref=$REGRESS_BASE; fi
  root=$(repo_root) || return 1
  if [ -n "$TAGS" ]; then
    tags=$(printf '%s' "$TAGS" | tr '\n' ' ')
  else
    base=$(diff_base HEAD "$ref") || return 1
    changed=$(changed_skills "$base" WT) || return 1
    statuses=$(tag_status WT <<<"$changed") || return 1
    tags=$(tagged_names <<<"$statuses")
    while read -r kind name status; do
      [ -n "$name" ] || continue
      if [ "$status" = untagged ]; then echo "WARNING: skill $name has no eval case tagged $name."; fi
    done <<<"$statuses"
  fi
  read -r -a tag_arr <<<"$tags"
  if [ ${#tag_arr[@]} -eq 0 ]; then
    echo "No changed skill has an eval case. Nothing to compare."
    return 0
  fi
  echo "Comparing $ref with the working tree for:$tags"
  echo "Cost ceiling: up to 2 x \$$REGRESS_MAX_COST_USD, one ceiling for each side."
  echo "The new side includes uncommitted edits in the working tree."
  wt_add "$ref" || return 1
  rm -rf "${WT_PATH:?}/evals"
  mkdir "$WT_PATH/evals"
  tar -C "$root/evals" --exclude './results' -cf - . | tar -C "$WT_PATH/evals" -xf -
  old_rows=$(run_and_score "$WT_PATH" "$RUN_TMP/old" WT "${tag_arr[@]}") || return 1
  new_rows=$(run_and_score "$root" "$RUN_TMP/new" WT "${tag_arr[@]}") || return 1
  compare_table "$old_rows" "$new_rows"
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
    --compare) shift; mode_compare "$@" ;;
    *) usage; exit 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
