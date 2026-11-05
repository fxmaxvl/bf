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

# The per-repo state file is the lock every hook checks.
_state_file() {
  echo "$HOME/.bf/autopilot/$(_derive_project_id).json"
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

# Claude Code reloads settings files, so a session already open in the repo gets the hooks too.
# The run belongs to the session that ran install.sh on. An empty ID on either side matches any session.
_owns_run() {
  local owner
  owner=$(jq -r '.session_id // empty' "$1" 2>/dev/null || true)
  [ -z "$owner" ] || [ -z "$2" ] || [ "$owner" = "$2" ]
}

# The start time guards against a new process that reuses the lead's PID.
_lead_alive() {
  local pid started
  pid=$(jq -r '.lead_pid // empty' "$1" 2>/dev/null || true)
  started=$(jq -r '.lead_started // empty' "$1" 2>/dev/null || true)
  [ -n "$pid" ] && [ -n "$started" ] || return 1
  [ "$(ps -p "$pid" -o lstart= 2>/dev/null || true)" = "$started" ]
}

# A scheduled prompt reaches UserPromptSubmit with no tag. stop.sh saves the prompts of the
# session's crons, which the Stop input lists, so a later turn can be matched against them.
# A prompt over 1000 characters is clipped there and ends in "… [+N chars]", so a clipped one
# matches on its prefix.
_is_cron_turn() {
  jq -e --arg p "$2" '
    (.cron_prompts // []) | any(
      if test("… \\[\\+[0-9]+ chars\\]$")
      then . as $c | ($c | sub("… \\[\\+[0-9]+ chars\\]$"; "")) as $head | ($p | startswith($head))
      else . == $p end)
  ' "$1" >/dev/null 2>&1
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
