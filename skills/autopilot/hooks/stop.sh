#!/usr/bin/env bash

set -euo pipefail

STOP_HOOK_ACTIVE=$(jq -r '.stop_hook_active // false' 2>/dev/null || printf 'false')

if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

STATE_FILE="$HOME/.vs/bf-autopilot/state.json"

[[ -f "$STATE_FILE" ]] || exit 0

jq -n '{decision: "block", reason: "bf:autopilot is active. Do not stop. Return to the autopilot SKILL.md and continue executing the current phase. Use critic for all decisions — do not wait for user input."}'