#!/usr/bin/env bash
# Smoke test for evals/regress.sh against throwaway repos and a stub `claude` on PATH.
# The stub never calls a model. Every run happens inside a temp repo, never in this repo.
#
# Usage: regress-smoke.sh
# Output: one PASS or FAIL line per case. Exit 0 when every case passes, 1 otherwise.
# shellcheck disable=SC2030,SC2031
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REGRESS=$here/regress.sh
fails=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP regress-smoke: jq is not installed"
  exit 0
fi

ROOT_TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$ROOT_TMP"' EXIT
ctx_n=0

unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE REGRESS_MARGIN REGRESS_MODEL REGRESS_JUDGE_MODEL \
  REGRESS_RUNS REGRESS_MAX_COST_USD REGRESS_CONCURRENCY REGRESS_BASE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.com
export GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.com

eq() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails + 1)); fi
}

has() {
  case "$2" in
    *"$3"*) echo "PASS $1" ;;
    *) echo "FAIL $1: got [$2], want it to contain [$3]"; fails=$((fails + 1)) ;;
  esac
}

# A unit call runs in a subshell with errexit on, so a function that relies on errexit
# behaves the same here as in a real run.
# shellcheck disable=SC1090,SC1091
rg() { ( cd "$CTX_REPO" && export PATH="$CTX_BIN:$PATH" STUB_DIR="$CTX_TMP" && set -euo pipefail && . "$REGRESS" && "$@" ); }

# Every script run goes through the stub `claude`, with stdin that is never a terminal.
rr() { ( cd "$CTX_REPO" && PATH="$CTX_BIN:$PATH" STUB_DIR="$CTX_TMP" "$REGRESS" "$@" </dev/null ); }

g() { git -C "$CTX_REPO" "$@"; }

t_conf_defaults() {
  make_ctx
  eq conf-defaults "$(rg eval 'conf_load origin/main; echo "$REGRESS_MAX_COST_USD $REGRESS_MARGIN $REGRESS_RUNS $REGRESS_CONCURRENCY $REGRESS_MODEL $REGRESS_JUDGE_MODEL $REGRESS_BASE"')" \
    "10 0.34 3 4 claude-sonnet-5-5 claude-haiku-5-5 origin/main"
}

t_conf_from_base() {
  make_ctx
  printf 'REGRESS_RUNS=5\nREGRESS_MARGIN=0.2\n' > "$CTX_REPO/evals/regress.conf"
  g add evals/regress.conf && g commit -qm conf && g push -q origin main
  eq conf-from-base "$(rg eval 'conf_load origin/main; echo "$REGRESS_RUNS $REGRESS_MARGIN"')" "5 0.2"
}

t_conf_env_wins() {
  make_ctx
  printf 'REGRESS_RUNS=5\n' > "$CTX_REPO/evals/regress.conf"
  g add evals/regress.conf && g commit -qm conf && g push -q origin main
  eq conf-env-wins "$(REGRESS_RUNS=7 rg eval 'conf_load origin/main; echo "$REGRESS_RUNS"')" "7"
}

t_conf_ignores_base_key() {
  make_ctx
  printf 'REGRESS_BASE=evil/branch\nREGRESS_RUNS=5\n' > "$CTX_REPO/evals/regress.conf"
  g add evals/regress.conf && g commit -qm conf && g push -q origin main
  eq conf-ignores-base-key "$(rg eval 'conf_load origin/main; echo "$REGRESS_BASE $REGRESS_RUNS"')" "origin/main 5"
}

t_conf_working_tree_edit() {
  make_ctx
  printf 'REGRESS_RUNS=5\n' > "$CTX_REPO/evals/regress.conf"
  g add evals/regress.conf && g commit -qm conf && g push -q origin main
  printf 'REGRESS_RUNS=9\n' > "$CTX_REPO/evals/regress.conf"
  eq conf-check-ignores-wt "$(rg eval 'conf_load "$(src_ref "$(src_for check conf)")"; echo "$REGRESS_RUNS"')" "5"
  eq conf-update-uses-wt "$(rg eval 'conf_load "$(src_ref "$(src_for update-baseline conf)")"; echo "$REGRESS_RUNS"')" "9"
}

t_src_for_table() {
  make_ctx
  local row mode input want got
  for row in \
    "pre-push plugin pushed" "pre-push cases pushed" "pre-push baseline base" "pre-push conf base" \
    "coverage plugin none" "coverage cases head" "coverage baseline none" "coverage conf base" \
    "check plugin head" "check cases head" "check baseline base" "check conf base" \
    "update-baseline plugin head" "update-baseline cases head" "update-baseline baseline wt" "update-baseline conf wt" \
    "compare-old plugin ref" "compare-old cases wt" "compare-old baseline none" "compare-old conf wt" \
    "compare-new plugin wt" "compare-new cases wt" "compare-new baseline none" "compare-new conf wt"; do
    read -r mode input want <<<"$row"
    got=$(rg src_for "$mode" "$input")
    eq "src-for-$mode-$input" "$got" "$want"
  done
}

t_src_ref() {
  make_ctx
  eq src-ref-head "$(rg src_ref head)" "HEAD"
  eq src-ref-base "$(rg src_ref base)" "origin/main"
  eq src-ref-wt "$(rg src_ref wt)" "WT"
  eq src-ref-pushed "$(rg src_ref pushed abc123)" "abc123"
  eq src-ref-none "$(rg src_ref none)" ""
}

t_read_at() {
  make_ctx
  echo "committed" > "$CTX_REPO/evals/note.txt"
  g add evals/note.txt && g commit -qm note
  echo "edited" > "$CTX_REPO/evals/note.txt"
  eq read-at-commit "$(rg read_at HEAD evals/note.txt)" "committed"
  eq read-at-wt "$(rg read_at WT evals/note.txt)" "edited"
}

t_usage_on_unknown_mode() {
  make_ctx
  local out rc
  out=$(rr --bogus 2>&1); rc=$?
  eq usage-exit "$rc" "1"
  has usage-text "$out" "Usage:"
}

t_missing_jq() {
  make_ctx
  local out rc
  out=$(cd "$CTX_REPO" && PATH=/nonexistent /bin/bash "$REGRESS" --check </dev/null 2>&1); rc=$?
  eq missing-jq-exit "$rc" "1"
  has missing-jq-text "$out" "jq"
}

# Writes one file of a fixture case. The caller commits when the case must exist at a commit.
put() {
  mkdir -p "$(dirname "$CTX_REPO/$1")"
  printf '%b' "$2" > "$CTX_REPO/$1"
}

t_meta_tags_flow_case_yaml() {
  make_ctx
  eq meta-tags-flow-case-yaml "$(rg case_meta HEAD alpha-case tags)" "alpha"
}

t_meta_tags_block_list() {
  make_ctx
  put evals/blk/case.yaml 'name: blk\ntags:\n  - x\n  - y\ncontext:\n  scaffold_script: s.sh\n'
  g add -A && g commit -qm blk
  eq meta-tags-block-list "$(rg case_meta HEAD blk tags | tr '\n' ' ')" "x y "
}

t_meta_tags_frontmatter() {
  make_ctx
  eq meta-tags-frontmatter "$(rg case_meta HEAD beta-case tags)" "beta"
}

t_meta_tags_both_files() {
  make_ctx
  put evals/both/case.yaml 'name: both\ntags: [a, b]\n'
  put evals/both/prompt.md '---\ntags: [b, c]\n---\nbody\n'
  g add -A && g commit -qm both
  eq meta-tags-both-files "$(rg case_meta HEAD both tags | tr '\n' ' ')" "a b c "
}

t_meta_allowed_tools() {
  make_ctx
  put evals/yml/case.yaml 'name: yml\nallowed_tools: [Bash, Read]\n'
  put evals/both/case.yaml 'name: both\nallowed_tools: [Bash]\n'
  put evals/both/prompt.md '---\nallowed_tools: [Bash, Write]\n---\nbody\n'
  g add -A && g commit -qm tools
  eq meta-tools-frontmatter "$(rg case_meta HEAD beta-case allowed_tools)" "Read"
  eq meta-tools-case-yaml "$(rg case_meta HEAD yml allowed_tools | tr '\n' ' ')" "Bash Read "
  eq meta-tools-both "$(rg case_meta HEAD both allowed_tools | tr '\n' ' ')" "Bash Write "
  eq meta-tools-absent "$(rg case_meta HEAD alpha-case allowed_tools)" ""
  rg case_meta HEAD alpha-case allowed_tools >/dev/null
  eq meta-tools-absent-exit "$?" "0"
}

t_meta_unreadable_key() {
  make_ctx
  put evals/odd/case.yaml 'name: odd\ntags: {a: 1}\n'
  g add -A && g commit -qm odd
  local out rc
  out=$(rg case_meta HEAD odd tags 2>&1); rc=$?
  eq meta-unreadable-exit "$rc" "1"
  has meta-unreadable-names-file "$out" "evals/odd/case.yaml"
}

t_meta_scalar_tags_unreadable() {
  make_ctx
  put evals/odd/prompt.md '---\ntags: alpha\n---\nbody\n'
  g add -A && g commit -qm odd
  rg case_meta HEAD odd tags >/dev/null 2>&1
  eq meta-scalar-unreadable-exit "$?" "1"
}

t_list_cases() {
  make_ctx
  put evals/results/prompt.md 'ignored\n'
  printf 'evals/results/\n' > "$CTX_REPO/.gitignore"
  eq list-cases-head "$(rg list_cases HEAD | tr '\n' ' ')" "alpha-case beta-case "
  put evals/gamma-case/case.yaml 'name: gamma-case\ntags: [gamma]\n'
  eq list-cases-ignores-uncommitted-at-head "$(rg list_cases HEAD | tr '\n' ' ')" "alpha-case beta-case "
  eq list-cases-wt-sees-uncommitted "$(rg list_cases WT | tr '\n' ' ')" "alpha-case beta-case gamma-case "
}

t_cases_with_tag() {
  make_ctx
  put evals/alpha-two/case.yaml 'name: alpha-two\ntags: [alpha, extra]\n'
  g add -A && g commit -qm two
  eq cases-with-tag "$(rg cases_with_tag HEAD alpha | tr '\n' ' ')" "alpha-case alpha-two "
  eq cases-with-tag-none "$(rg cases_with_tag HEAD nothing)" ""
}

t_case_tree() {
  make_ctx
  local before after
  before=$(rg case_tree HEAD alpha-case)
  put evals/alpha-case/.DS_Store 'junk'
  after=$(rg case_tree HEAD alpha-case)
  eq case-tree-stable-with-stray-file "$after" "$before"
  eq case-tree-is-git-tree "$before" "$(g rev-parse HEAD:evals/alpha-case)"
  eq case-tree-absent "$(rg case_tree HEAD no-such-case)" ""
  rg case_tree HEAD no-such-case >/dev/null
  eq case-tree-absent-exit "$?" "0"
}

t_changed_skills_edit() {
  make_ctx
  put skills/alpha/x.md 'x\n'
  g add -A && g commit -qm x
  eq changed-edit "$(rg changed_skills origin/main HEAD)" "edited alpha"
}

t_changed_skills_nested_once() {
  make_ctx
  put skills/alpha/x.md 'x\n'
  put skills/alpha/sub/SKILL.md '# sub\n'
  g add -A && g commit -qm nested
  eq changed-nested-once "$(rg changed_skills origin/main HEAD)" "edited alpha"
}

t_changed_skills_added() {
  make_ctx
  put skills/gamma/SKILL.md '# gamma\n'
  g add -A && g commit -qm gamma
  eq changed-added "$(rg changed_skills origin/main HEAD)" "added gamma"
}

t_changed_skills_ignores_non_skills() {
  make_ctx
  put skills/SMOKE-TESTS.md 'changed\n'
  g add -A && g commit -qm doc
  eq changed-smoke-tests-only "$(rg changed_skills origin/main HEAD)" ""
  g rm -rq skills/beta && g commit -qm rm
  eq changed-deleted-skill "$(rg changed_skills origin/main HEAD)" ""
  put skills/delta/notes.md 'n\n'
  g add -A && g commit -qm delta
  eq changed-dir-without-skill-md "$(rg changed_skills origin/main HEAD)" ""
}

t_changed_skills_working_tree() {
  make_ctx
  put skills/alpha/x.md 'uncommitted\n'
  put skills/gamma/SKILL.md '# gamma\n'
  eq changed-wt "$(rg changed_skills origin/main WT | tr '\n' ',')" "edited alpha,added gamma,"
  eq changed-head-sees-nothing "$(rg changed_skills origin/main HEAD)" ""
}

add_gamma() {
  put skills/gamma/SKILL.md '# gamma\n'
  if [ "${1:-}" = case ]; then put evals/gamma-case/case.yaml 'name: gamma-case\ntags: [gamma]\n'; fi
  g add -A && g commit -qm gamma
}

t_coverage_unit() {
  make_ctx
  add_gamma case
  printf 'added gamma\n' | rg coverage HEAD >/dev/null 2>&1
  eq coverage-added-with-case "$?" "0"
  printf 'added beta\n' | rg coverage HEAD >/dev/null 2>&1
  eq coverage-frontmatter-tag-counts "$?" "0"
  local out rc
  out=$(printf 'added delta\n' | rg coverage HEAD 2>&1); rc=$?
  eq coverage-added-without-case-exit "$rc" "1"
  has coverage-names-skill "$out" "delta"
  has coverage-names-tag "$out" "tagged delta"
  out=$(printf 'edited delta\n' | rg coverage HEAD 2>&1); rc=$?
  eq coverage-edited-without-case-exit "$rc" "0"
  has coverage-edited-warns "$out" "WARNING"
}

t_coverage_mode() {
  make_ctx
  g switch -qc feat
  add_gamma
  local out rc
  out=$(rr --coverage 2>&1); rc=$?
  eq coverage-mode-blocks-uncovered "$rc" "1"
  has coverage-mode-message "$out" "gamma"
  put evals/gamma-case/case.yaml 'name: gamma-case\ntags: [gamma]\n'
  out=$(rr --coverage 2>&1); rc=$?
  eq coverage-mode-ignores-uncommitted-case "$rc" "1"
  g add -A && g commit -qm case
  rr --coverage >/dev/null 2>&1
  eq coverage-mode-passes-covered "$?" "0"
  eq coverage-mode-makes-no-claude-call "$([ -e "$CTX_TMP/claude-args" ] && echo called || echo none)" "none"
}

t_coverage_fetch_failure() {
  make_ctx
  g switch -qc feat
  add_gamma
  g remote set-url origin "$CTX_TMP/missing.git"
  local out rc
  out=$(rr --coverage 2>&1); rc=$?
  eq coverage-fetch-failure-verdict "$rc" "1"
  has coverage-fetch-failure-warning "$out" "WARNING: could not fetch origin/main, using a copy from"
}

t_base_mb() {
  make_ctx
  local base
  base=$(g rev-parse HEAD)
  g switch -qc feat
  add_gamma
  eq base-mb-is-merge-base "$(rg base_mb HEAD)" "$base"
}

# The same as rr, with the given text on stdin. It is the hook seam.
rr_in() {
  local input=$1
  shift
  ( cd "$CTX_REPO" && PATH="$CTX_BIN:$PATH" STUB_DIR="$CTX_TMP" "$REGRESS" "$@" <<<"$input" )
}

ZERO=0000000000000000000000000000000000000000

t_prepush_targets() {
  make_ctx
  local base main_sha feat1 feat2 out rc
  main_sha=$(g rev-parse HEAD)
  base=$main_sha
  g switch -qc feat
  add_gamma
  feat1=$(g rev-parse HEAD)
  put skills/alpha/y.md 'y\n'
  g add -A && g commit -qm y
  feat2=$(g rev-parse HEAD)
  eq prepush-delete-skipped "$(rg prepush_targets <<<"refs/heads/x $ZERO refs/heads/x $feat1")" ""
  eq prepush-new-branch "$(rg prepush_targets <<<"refs/heads/feat $feat2 refs/heads/feat $ZERO")" "$feat2 $base"
  eq prepush-unknown-remote-sha "$(rg prepush_targets <<<"refs/heads/feat $feat2 refs/heads/feat deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")" "$feat2 $base"
  eq prepush-normal-update "$(rg prepush_targets <<<"refs/heads/feat $feat2 refs/heads/feat $feat1")" "$feat2 $feat1"
  eq prepush-same-sha-once "$(rg prepush_targets <<<"refs/heads/a $feat2 refs/heads/a $ZERO
refs/heads/b $feat2 refs/heads/b $ZERO" | wc -l | tr -d ' ')" "1"
  eq prepush-two-shas "$(rg prepush_targets <<<"refs/heads/a $feat2 refs/heads/a $ZERO
refs/heads/b $feat1 refs/heads/b $ZERO" | wc -l | tr -d ' ')" "2"
  g switch -q --orphan lone && g commit -qm lone --allow-empty
  out=$(REGRESS_BASE=origin/nothing rg prepush_targets <<<"refs/heads/lone $(g rev-parse HEAD) refs/heads/lone $ZERO" 2>&1); rc=$?
  eq prepush-no-merge-base-exit "$rc" "1"
  has prepush-no-merge-base-reminder "$out" "git push --no-verify"
}

t_prepush_free_path() {
  make_ctx
  local sha
  g switch -qc feat
  put skills/SMOKE-TESTS.md 'changed\n'
  g add -A && g commit -qm doc
  sha=$(g rev-parse HEAD)
  g remote set-url origin "$CTX_TMP/missing.git"
  local out rc
  out=$(rr_in "refs/heads/feat $sha refs/heads/feat $ZERO" --pre-push origin url 2>&1); rc=$?
  eq prepush-free-path-exit "$rc" "0"
  eq prepush-free-path-no-fetch "$out" ""
  eq prepush-free-path-no-claude "$([ -e "$CTX_TMP/claude-args" ] && echo called || echo none)" "none"
}

# Puts the hook and the script into the clone and enables the hook there.
install_hook() {
  mkdir -p "$CTX_REPO/.githooks"
  cp "$here/../.githooks/pre-push" "$CTX_REPO/.githooks/pre-push"
  cp "$REGRESS" "$CTX_REPO/evals/regress.sh"
  g add -A && g commit -qm hook && g push -q --no-verify origin main
  g config core.hooksPath .githooks
}

push_feat() { ( cd "$CTX_REPO" && PATH="$CTX_BIN:$PATH" STUB_DIR="$CTX_TMP" git push "$@" origin feat 2>&1 </dev/null ); }

t_hook_e2e_coverage_gate() {
  make_ctx
  install_hook
  g switch -qc feat
  add_gamma
  local out rc
  out=$(push_feat); rc=$?
  eq hook-blocks-uncovered-skill "$([ "$rc" -ne 0 ] && echo blocked || echo pushed)" "blocked"
  has hook-block-message "$out" "skill gamma is new and has no eval case"
  out=$(push_feat --no-verify); rc=$?
  eq hook-no-verify-pushes "$rc" "0"
  g push -q origin --delete feat
  put evals/gamma-case/case.yaml 'name: gamma-case\ntags: [gamma]\n'
  g add -A && g commit -qm case
  out=$(push_feat); rc=$?
  eq hook-allows-covered-skill "$rc" "0"
}

# Builds a result file for the stub. Each argument is name=score,score,... where a score is a
# number, "err" for an errored run or "skip" for a run whose paid graders were skipped.
fx() {
  local out=$1 spec name scores runs arr="[]"
  shift
  for spec in "$@"; do
    name=${spec%%=*}
    scores=${spec#*=}
    runs=$(jq -cn --arg s "$scores" '$s | split(",") | map(
      if . == "err" then {score: 0, error: "interrupted", skippedPaidGraders: false}
      elif . == "skip" then {score: 0.5, error: null, skippedPaidGraders: true}
      else {score: tonumber, error: null, skippedPaidGraders: false} end
      | . + {costUsd: 1, durationSeconds: 10})')
    arr=$(jq -cn --argjson a "$arr" --arg n "$name" --argjson r "$runs" '$a + [{name: $n, arms: {with: $r}}]')
  done
  jq -n --argjson c "$arr" '{partial: false, partialReason: null,
    costUsd: ($c | map(.arms.with | map(.costUsd) | add) | add),
    durationSeconds: ($c | map(.arms.with | map(.durationSeconds) | add) | add), cases: $c}' > "$out"
}

# Runs inside rg, where the script is sourced.
do_score() {
  conf_load HEAD
  run_and_score "$@"
}

# Runs run_and_score through the stub. The first argument is the result file the stub returns.
score() {
  local json=$1
  shift
  mkdir -p "$CTX_TMP/plug"
  STUB_JSON=$json rg do_score "$CTX_TMP/plug" "$CTX_TMP/out" HEAD "$@" </dev/null
}

t_score_argv_order() {
  make_ctx
  put evals/gamma-case/case.yaml 'name: gamma-case\ntags: [gamma]\nallowed_tools: [Bash, Read]\n'
  put evals/gamma-case/prompt.md '---\nallowed_tools: [Write, Bash, mcp__x__y]\n---\nbody\n'
  g add -A && g commit -qm gamma
  fx "$CTX_TMP/r.json" gamma-case=1,1,1
  score "$CTX_TMP/r.json" gamma >/dev/null 2>&1
  local want
  want="--call plugin eval $CTX_TMP/plug --ablation none --threshold 0 --model claude-sonnet-5-5 --judge-model claude-haiku-5-5 --runs 3 --max-cost-usd 10 -j 4 --scaffold --trust-plugin --no-publish --json $CTX_TMP/out/result.json --output-dir $CTX_TMP/out/out --report $CTX_TMP/out/report.html --tag gamma --allow-tools Bash Write mcp__x__y "
  eq score-argv-order "$(tr '\n' ' ' < "$CTX_TMP/claude-args")" "$want"
  eq score-writes-nothing-in-plugin-dir "$([ -e "$CTX_TMP/plug/evals/results" ] && echo found || echo none)" "none"
}

t_score_no_gated_tool() {
  make_ctx
  fx "$CTX_TMP/r.json" beta-case=1,1,1
  score "$CTX_TMP/r.json" beta >/dev/null 2>&1
  has score-no-gated-tool-flag-absent "$(tr '\n' ' ' < "$CTX_TMP/claude-args")" "--tag beta "
  eq score-no-allow-tools "$(grep -c -e '^--allow-tools$' "$CTX_TMP/claude-args")" "0"
}

t_score_means_counted_runs() {
  make_ctx
  fx "$CTX_TMP/r.json" alpha-case=1,0.6,0.6
  eq score-mean "$(score "$CTX_TMP/r.json" alpha 2>&1 | tr '\t' ' ')" "alpha-case 0.733 3 3"
  fx "$CTX_TMP/r.json" alpha-case=1,1,err
  eq score-errored-run-not-counted "$(REGRESS_RUNS=2 score "$CTX_TMP/r.json" alpha 2>&1 | tr '\t' ' ')" "alpha-case 1 2 2"
  fx "$CTX_TMP/r.json" alpha-case=1,1,skip
  eq score-skipped-graders-not-counted "$(REGRESS_RUNS=2 score "$CTX_TMP/r.json" alpha 2>&1 | tr '\t' ' ')" "alpha-case 1 2 2"
}

t_score_fails_closed() {
  make_ctx
  local out rc
  fx "$CTX_TMP/r.json" alpha-case=1,1,1
  out=$(STUB_EXIT=2 score "$CTX_TMP/r.json" alpha 2>&1); rc=$?
  eq score-exit-2-fails "$rc" "1"
  has score-exit-2-reason "$out" "partial run"
  has score-reminds-no-verify "$out" "git push --no-verify"
  out=$(STUB_EXIT=1 score "$CTX_TMP/r.json" alpha 2>&1); rc=$?
  eq score-exit-1-fails "$rc" "1"
  has score-exit-1-reason "$out" "exited with status 1"
  jq '.partial = true | .partialReason = "cost ceiling"' "$CTX_TMP/r.json" > "$CTX_TMP/p.json"
  out=$(score "$CTX_TMP/p.json" alpha 2>&1); rc=$?
  eq score-partial-flag-fails "$rc" "1"
  has score-partial-flag-reason "$out" "cost ceiling"
  out=$(score "$CTX_TMP/r.json" alpha beta 2>&1); rc=$?
  eq score-missing-case-fails "$rc" "1"
  has score-missing-case-names-case "$out" "beta-case"
  fx "$CTX_TMP/r.json" alpha-case=1,1,err
  out=$(score "$CTX_TMP/r.json" alpha 2>&1); rc=$?
  eq score-too-few-runs-fails "$rc" "1"
  has score-too-few-runs-names-case "$out" "alpha-case has 2 counted runs of 3"
}

t_score_stdin_is_closed() {
  make_ctx
  fx "$CTX_TMP/r.json" alpha-case=1,1,1
  mkdir -p "$CTX_TMP/plug"
  STUB_JSON=$CTX_TMP/r.json rg do_score "$CTX_TMP/plug" "$CTX_TMP/out" HEAD alpha >/dev/null <<<"ref lines the hook must keep"
  eq score-child-stdin-bytes "$(cat "$CTX_TMP/claude-stdin")" "0"
}

t_wt_add_and_cleanup() {
  make_ctx
  local out
  out=$(rg eval 'GIT_DIR=.git GIT_WORK_TREE=. wt_add HEAD; git -C "$WT_PATH" log --oneline | wc -l | tr -d " "; wt_cleanup; [ -e "$WT_PATH" ] && echo present || echo gone' | tr '\n' ' ')
  eq wt-add-works-with-hook-env "$out" "1 gone "
  eq wt-cleanup-leaves-no-worktree "$(g worktree list | wc -l | tr -d ' ')" "1"
}

t_wt_removed_on_interrupt() {
  make_ctx
  fx "$CTX_TMP/r.json" alpha-case=1,1,1
  cat > "$CTX_TMP/drive.sh" <<DRIVER
. "$REGRESS"
conf_load HEAD
wt_add HEAD
run_and_score "\$WT_PATH" "\$RUN_TMP/o" HEAD alpha
DRIVER
  set -m
  ( cd "$CTX_REPO" && PATH="$CTX_BIN:$PATH" STUB_DIR="$CTX_TMP" STUB_JSON="$CTX_TMP/r.json" STUB_SLEEP=3 exec bash "$CTX_TMP/drive.sh" </dev/null >/dev/null 2>&1 ) &
  local pid=$!
  sleep 1
  kill -INT -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  set +m
  eq wt-interrupt-stub-was-running "$([ -e "$CTX_TMP/claude-args" ] && echo yes || echo no)" "yes"
  eq wt-interrupt-removes-worktree "$(g worktree list | wc -l | tr -d ' ')" "1"
}

run_tests() {
  local t
  for t in $(compgen -A function t_); do "$t"; done
  [ "$fails" -eq 0 ]
}

make_ctx() {
  ctx_n=$((ctx_n + 1))
  CTX_TMP=$ROOT_TMP/ctx$ctx_n
  CTX_REPO=$CTX_TMP/repo
  CTX_ORIGIN=$CTX_TMP/origin.git
  CTX_BIN=$CTX_TMP/bin
  mkdir -p "$CTX_BIN" "$CTX_REPO"
  cat > "$CTX_BIN/claude" <<'STUB'
#!/bin/bash
d=${STUB_DIR:?}
{ echo "--call"; printf '%s\n' "$@"; } >> "$d/claude-args"
wc -c | tr -d ' ' >> "$d/claude-stdin"
json=""; prev=""
for a in "$@"; do [ "$prev" = --json ] && json=$a; prev=$a; done
if [ -n "$json" ] && [ -n "${STUB_JSON:-}" ]; then cp "$STUB_JSON" "$json"; fi
if [ -n "${STUB_SLEEP:-}" ]; then sleep "$STUB_SLEEP"; fi
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$CTX_BIN/claude"
  if [ "$(PATH="$CTX_BIN:$PATH" command -v claude)" != "$CTX_BIN/claude" ]; then
    echo "ABORT: the stub claude is not first on PATH" >&2
    exit 2
  fi
  git init -q -b main "$CTX_ORIGIN" --bare
  git init -q -b main "$CTX_REPO"
  mkdir -p "$CTX_REPO/skills/alpha" "$CTX_REPO/skills/beta" "$CTX_REPO/evals/alpha-case" "$CTX_REPO/evals/beta-case"
  echo "# alpha" > "$CTX_REPO/skills/alpha/SKILL.md"
  echo "# beta" > "$CTX_REPO/skills/beta/SKILL.md"
  echo "# smoke tests" > "$CTX_REPO/skills/SMOKE-TESTS.md"
  printf 'schema_version: "1.1"\nname: alpha-case\ntags: [alpha]\n' > "$CTX_REPO/evals/alpha-case/case.yaml"
  printf -- '---\ndescription: beta\ntags: [beta]\nallowed_tools: [Read]\n---\nrun beta\n' > "$CTX_REPO/evals/beta-case/prompt.md"
  git -C "$CTX_REPO" add -A
  git -C "$CTX_REPO" commit -qm seed
  git -C "$CTX_REPO" remote add origin "$CTX_ORIGIN"
  git -C "$CTX_REPO" push -q origin main
  git -C "$CTX_REPO" fetch -q origin
}

run_tests
