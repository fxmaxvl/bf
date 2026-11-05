#!/usr/bin/env bash
# A new session in the repo must not keep a run, and its bypass mode, from a session that ended.
# A second session that starts while the lead still runs leaves the lead's run alone.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"

SESSION_ID=$(jq -r '.session_id // empty' 2>/dev/null || true)
STATE_FILE="$HOME/.bf/autopilot/$(_derive_project_id).json"

if [[ -n "$SESSION_ID" && -f "$STATE_FILE" ]] && ! _owns_run "$STATE_FILE" "$SESSION_ID" && _lead_alive "$STATE_FILE"; then
  exit 0
fi

bash "$SCRIPT_DIR/install.sh" off >/dev/null 2>&1 || true

exit 0
