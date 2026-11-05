#!/usr/bin/env bash
# Shared helpers for autopilot hooks. Source this file; do not execute directly.

# Derive a stable project identifier from the git remote URL, falling back to
# the repository basename. This is the single source of truth — install.sh and
# stop.sh both source this file instead of duplicating the derivation.
_derive_project_id() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local pid
  pid=$(git config --get remote.origin.url 2>/dev/null \
    | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
  [ -z "$pid" ] && pid=$(basename "$repo_root")
  echo "$pid"
}

# A word list cannot read intent: it misses "please stop" and stops on "no, keep going". So the
# hook ends the run itself only on one bare word, and leaves every other stop request to the model.
_is_stop_prompt() {
  local words
  words=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z' ' ')
  # shellcheck disable=SC2086
  set -- $words
  [ "$#" -eq 1 ] || return 1
  case $1 in stop|cancel|abort|quit|exit) return 0 ;; esac
  return 1
}

# The hook input has no field for the source of a turn. Task notifications and messages from
# other sessions reach UserPromptSubmit too, and only their opening tag tells them apart.
_is_agent_turn() {
  local head
  head=$(printf '%s' "$1" | sed -n '/[^[:space:]]/{p;q;}' | sed 's/^[[:space:]]*//')
  case $head in
    '<task-notification'*|'<teammate-message'*|'<cross-session-message'*) return 0 ;;
  esac
  return 1
}
