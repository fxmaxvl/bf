#!/usr/bin/env bash

set -euo pipefail

INPUT=$(cat)
field() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null || true; }

if [[ "$(field '.stop_hook_active // false')" == "true" ]]; then
  exit 0
fi

# Settings hooks also fire in sub-agents and teammates. Only the lead session runs the workflow.
[[ -z "$(field '.agent_id // empty')" ]] || exit 0

# Claude Code wakes the session when background work ends, so a stop while it runs is a pause.
case "$(field '(.background_tasks // []) | length')" in
  ''|0) ;;
  *) exit 0 ;;
esac

# Derive PROJECT_ID via shared helper (same derivation as install.sh).
# stop.sh assumes it runs in the project cwd (Claude Code Stop hook behaviour).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"
PROJECT_ID=$(_derive_project_id)

# Check per-repo file (not global state.json) — it is the per-repo lock.
# See install.sh for the two-step write invariant.
REPO_STATE_FILE="$HOME/.bf/autopilot/${PROJECT_ID}.json"

[[ -f "$REPO_STATE_FILE" ]] || exit 0

jq -n '{decision: "block", reason: "bf:autopilot is active. Do not stop. Return to the autopilot SKILL.md and continue executing the current phase. Use critic for all decisions — do not wait for user input."}'
