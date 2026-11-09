#!/usr/bin/env bash
# Smoke test for evals/regress.sh against throwaway repos and a stub `claude` on PATH.
# The stub never calls a model. Every run happens inside a temp repo, never in this repo.
#
# Usage: regress-smoke.sh
# Output: one PASS or FAIL line per case. Exit 0 when every case passes, 1 otherwise.
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
rg() { ( cd "$CTX_REPO" && set -euo pipefail && . "$REGRESS" && "$@" ); }

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
