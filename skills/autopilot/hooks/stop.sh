#!/usr/bin/env bash

set -euo pipefail

INPUT=$(cat)
field() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null || true; }

if [[ "$(field '.stop_hook_active // false')" == "true" ]]; then
  exit 0
fi

# Settings hooks also fire in sub-agents and teammates. Only the lead session runs the workflow.
[[ -z "$(field '.agent_id // empty')" ]] || exit 0

# A stop is a pause only while work runs that wakes the session when it ends: an agent, a
# workflow, or a one-shot wakeup. A shell task can run forever (a dev server, tail -f), so it
# does not count, or the run would stall with bypass mode on.
WAKERS='[(.background_tasks // [])[] | select(.type == "subagent" or .type == "teammate" or .type == "workflow" or .type == "cloud session")]
  + [(.session_crons // [])[] | select(.recurring == false)] | length'
case "$(field "$WAKERS")" in
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

jq -n --arg off "bash $SCRIPT_DIR/install.sh off" '{decision: "block", reason: ("bf:autopilot is active. If the user asked to stop or end autopilot, run `" + $off + "` and then stop. Otherwise return to the autopilot SKILL.md and continue the current phase. Use the oracle for all decisions and do not wait for user input.")}'
