#!/usr/bin/env bash
# A short stop prompt ends the run. Any other prompt keeps autopilot on and tells the model
# to do what the prompt asks first. Input that cannot be read ends the run, because bypass
# mode is on while autopilot runs.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"

INPUT=$(cat)
if ! PROMPT=$(printf '%s' "$INPUT" | jq -er '.prompt' 2>/dev/null) || _is_stop_prompt "$PROMPT"; then
  bash "$SCRIPT_DIR/install.sh" off >/dev/null 2>&1 || true
  exit 0
fi

PROJECT_ID=$(_derive_project_id)
[[ -f "$HOME/.bf/autopilot/${PROJECT_ID}.json" ]] || exit 0

jq -n '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: "bf:autopilot is still running. Do what this prompt asks first, including any change of direction. Then continue the run. The user can type stop to end it."}}'
