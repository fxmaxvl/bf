#!/usr/bin/env bash
# A new session in the repo must not keep a run, and its bypass mode, from a session that ended.
# The lead's own process ends the run, even when /clear gives it a new session ID. A second session
# that starts while the lead still runs leaves the run alone and gets a warning.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)
STATE_FILE=$(_state_file)

# Without CLAUDE_PID a clear is the only sign of the lead's own session.
from_lead() {
  local lead_pid
  lead_pid=$(jq -r '.lead_pid // empty' "$STATE_FILE" 2>/dev/null || true)
  if [[ -n "${CLAUDE_PID:-}" ]]; then
    [[ "$CLAUDE_PID" == "$lead_pid" ]]
  else
    [[ "$SOURCE" == "clear" ]]
  fi
}

if [[ -n "$SESSION_ID" && -f "$STATE_FILE" ]] && ! _owns_run "$STATE_FILE" "$SESSION_ID" \
  && ! from_lead && _lead_alive "$STATE_FILE"; then
  MSG="Another session's bf:autopilot run is active in this repo. It turned permission checks off (bypassPermissions in .claude/settings.local.json). To end the run and restore the setting, run: bash $SCRIPT_DIR/install.sh off"
  jq -n --arg m "$MSG" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
  exit 0
fi

bash "$SCRIPT_DIR/install.sh" off >/dev/null 2>&1 || true

exit 0
