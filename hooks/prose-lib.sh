#!/usr/bin/env bash
# Shared helpers for the prose hooks. Source this file; do not execute it.
#
# A hook must never break a session, and Claude Code reads exit 2 as a block. The EXIT trap makes
# every hook end with exit 0 whatever fails. Each caller captures the lint result as
# `rc=0; out=$(prose_lint ...) || rc=$?`, so the lint exit 1 (a hard marker) is data, not a failure.
trap 'exit 0' EXIT

# Found from this file, never from CLAUDE_PLUGIN_ROOT, so the hooks also run outside Claude Code.
_prose_hooks_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_prose_lint_script=$_prose_hooks_dir/../skills/plain/scripts/prose-lint.sh

PROSE_INPUT=

prose_off() { [ "${BF_PROSE_HOOK:-}" = off ]; }

# Reads the hook input once. Input that is not JSON, or a missing jq, ends the hook with exit 0.
prose_read_raw() { PROSE_INPUT=$(cat); }

prose_validate_input() { printf '%s' "$PROSE_INPUT" | jq -e . >/dev/null 2>&1 || exit 0; }

prose_read_input() {
  prose_read_raw
  prose_validate_input
}

prose_field() { printf '%s' "$PROSE_INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }

prose_cwd() {
  local c
  c=$(prose_field .cwd)
  printf '%s' "${c:-$PWD}"
}

# prose_lint <cwd> <mode> [extra args]: the text to lint arrives on stdin.
# Returns 0 or 1 with the JSON result on stdout, or 2 with no output when the lint gave no result.
# The caller needs the cwd because the project tier of the convention lookup depends on it.
prose_lint() {
  local cwd=$1 mode=$2 out rc=0
  shift 2
  out=$(bash "$_prose_lint_script" - --mode "$mode" --cwd "$cwd" --format json "$@" 2>/dev/null) || rc=$?
  case $rc in
    0|1) printf '%s\n' "$out"; return "$rc" ;;
    *) return 2 ;;
  esac
}

prose_digest() {
  bash "$_prose_lint_script" --digest --cwd "$1" 2>/dev/null
}

# prose_context <event> <text>: hookEventName must equal the name of the event that fired.
prose_context() {
  jq -n --arg e "$1" --arg t "$2" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$t}}'
}
