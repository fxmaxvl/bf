#!/usr/bin/env bash
# Shared helpers for the prose hooks. Source this file. Do not execute it.
#
# A hook must never break a session, and Claude Code reads exit 2 as a block. The EXIT trap makes
# every hook end with exit 0 whatever fails. Each caller captures the lint result as
# `rc=0; out=$(prose_lint ...) || rc=$?`, so the lint exit 1 (a hard marker) is data, not a failure.
trap 'exit 0' EXIT

# Found from this file, never from CLAUDE_PLUGIN_ROOT, so the hooks also run outside Claude Code.
_prose_hooks_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_prose_lint_script=$_prose_hooks_dir/../skills/plain/scripts/prose-lint.sh

prose_off() { [ "${BF_PROSE_HOOK:-}" = off ]; }

# Reads the hook input once. Input that is not JSON, or a missing jq, ends the hook with exit 0.
prose_read_raw() { PROSE_INPUT=$(cat); }

prose_validate_input() { printf '%s' "$PROSE_INPUT" | jq -e . >/dev/null 2>&1 || exit 0; }

prose_read_input() {
  prose_read_raw
  prose_validate_input
}

# prose_field <jq path>: needs PROSE_INPUT, so call prose_read_raw or prose_read_input first. When PROSE_INPUT is
# unset, the shell prints the error to stderr and the call returns nothing.
prose_field() {
  : "${PROSE_INPUT?prose_field called before prose_read_raw}"
  printf '%s' "$PROSE_INPUT" | jq -r "$1 // empty" 2>/dev/null || true
}

# prose_cwd: the cwd of the hook input. It has the same precondition as prose_field.
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

# prose_classify <path>: prints "<mode> [ext]" for a supported path. Fails for any other path.
prose_classify() {
  bash "$_prose_lint_script" --classify "$1" 2>/dev/null
}

prose_digest() {
  bash "$_prose_lint_script" --digest --cwd "$1" 2>/dev/null
}

# prose_context <event> <text>: hookEventName must equal the name of the event that fired.
prose_context() {
  jq -n --arg e "$1" --arg t "$2" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$t}}'
}

# Record of the last reply, for the Stop and UserPromptSubmit pair. It lives in a per-user 0700 directory
# because a shared /tmp can hold a directory that another user made first, and mkdir -m does not change
# an existing one. BF_PROSE_RECORD_ROOT and BF_PROSE_UID are the test seam for the owner check.
_prose_record_uid() { printf '%s' "${BF_PROSE_UID:-$(id -u)}"; }

_prose_record_dir() { printf '%s/bf-prose-%s' "${BF_PROSE_RECORD_ROOT:-${TMPDIR:-/tmp}}" "$(_prose_record_uid)"; }

# prose_record_path <session_id>: fails when nothing is left of the id after sanitizing.
prose_record_path() {
  local sid
  sid=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-')
  [ -n "$sid" ] || return 1
  printf '%s/%s' "$(_prose_record_dir)" "$sid"
}

# Ls prints the owner uid in field 3 on both BSD and GNU, where stat flags differ.
_prose_record_dir_owned() {
  local dir=$1 owner
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  owner=$(ls -nd "$dir" | awk '{print $3}')
  [ "$owner" = "$(_prose_record_uid)" ]
}

prose_record_dir_ok() {
  local dir=$1
  [ ! -L "$dir" ] || return 1
  mkdir -p -m 700 "$dir" 2>/dev/null || return 1
  _prose_record_dir_owned "$dir"
}

# prose_record_write <session_id> <line>: overwrites the record. It never appends, because autopilot can
# stop many times before the next prompt.
prose_record_write() {
  local path
  path=$(prose_record_path "$1") || return 0
  prose_record_dir_ok "$(dirname "$path")" || return 0
  [ ! -L "$path" ] || return 0
  printf '%s\n' "$2" > "$path"
}

# prose_record_take <session_id>: prints the record, then deletes it.
prose_record_take() {
  local path line
  path=$(prose_record_path "$1") || return 0
  _prose_record_dir_owned "$(dirname "$path")" || return 0
  [ -f "$path" ] && [ ! -L "$path" ] || return 0
  line=$(cat "$path")
  rm -f "$path"
  printf '%s' "$line"
}

prose_record_clear() {
  local path
  path=$(prose_record_path "$1") || return 0
  _prose_record_dir_owned "$(dirname "$path")" || return 0
  rm -f "$path"
}
