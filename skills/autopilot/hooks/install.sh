#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-}"

SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
HOOK_PATH="$SKILL_DIR/hooks/stop.sh"
CLEANUP_PATH="$SKILL_DIR/hooks/session-start-cleanup.sh"
PROMPT_CLEANUP_PATH="$SKILL_DIR/hooks/user-prompt-cleanup.sh"
chmod +x "$HOOK_PATH" "$CLEANUP_PATH" "$PROMPT_CLEANUP_PATH"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
STATE_DIR="$HOME/.bf/autopilot"
STATE_FILE="$STATE_DIR/state.json"

CLAUDE_SETTINGS="$REPO_ROOT/.claude/settings.local.json"

add_hook() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  [[ -f "$path" ]] || echo '{}' > "$path"
  local tmp
  tmp=$(mktemp)
  jq --arg stop_cmd "$HOOK_PATH" --arg start_cmd "$CLEANUP_PATH" --arg prompt_cmd "$PROMPT_CLEANUP_PATH" '
    .hooks = (.hooks // {}) |
    .hooks.Stop = (
      [(.hooks.Stop // [])[] | select(.__tag != "bf-autopilot-stop")] +
      [{ __tag: "bf-autopilot-stop",
         matcher: "",
         hooks: [{ type: "command", command: $stop_cmd }] }]
    ) |
    .hooks.SessionStart = (
      [(.hooks.SessionStart // [])[] | select(.__tag != "bf-autopilot-cleanup")] +
      [{ __tag: "bf-autopilot-cleanup",
         matcher: "",
         hooks: [{ type: "command", command: $start_cmd }] }]
    ) |
    .hooks.UserPromptSubmit = (
      [(.hooks.UserPromptSubmit // [])[] | select(.__tag != "bf-autopilot-user-cleanup")] +
      [{ __tag: "bf-autopilot-user-cleanup",
         matcher: "",
         hooks: [{ type: "command", command: $prompt_cmd }] }]
    )
  ' "$path" > "$tmp" && mv "$tmp" "$path"
}

remove_hook() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  local tmp
  tmp=$(mktemp)
  jq '
    if .hooks.Stop then
      .hooks.Stop |= [.[] | select(.__tag != "bf-autopilot-stop")]
    else . end
    | if .hooks.SessionStart then
        .hooks.SessionStart |= [.[] | select(.__tag != "bf-autopilot-cleanup")]
      else . end
    | if .hooks.UserPromptSubmit then
        .hooks.UserPromptSubmit |= [.[] | select(.__tag != "bf-autopilot-user-cleanup")]
      else . end
    | if (.hooks.Stop // []) | length == 0 then del(.hooks.Stop) else . end
    | if (.hooks.SessionStart // []) | length == 0 then del(.hooks.SessionStart) else . end
    | if (.hooks.UserPromptSubmit // []) | length == 0 then del(.hooks.UserPromptSubmit) else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$path" > "$tmp" && mv "$tmp" "$path"
}

case "$ACTION" in
  on)
    mkdir -p "$STATE_DIR"
    jq -n '{active: true}' > "$STATE_FILE"

    add_hook "$CLAUDE_SETTINGS"

    echo "bf:autopilot hook installed."
    echo "state: $STATE_FILE"
    echo
    echo "To stop autopilot:"
    echo "  - type anything at the prompt (UserPromptSubmit hook wipes state)"
    echo "  - close/reopen Claude Code (SessionStart hook wipes state)"
    echo "  - manual:  bash $SKILL_DIR/hooks/install.sh off"
    echo "  - nuclear: rm $STATE_FILE"
    ;;
  off)
    rm -f "$STATE_FILE"
    remove_hook "$CLAUDE_SETTINGS"
    echo "bf:autopilot hook removed."
    ;;
  *)
    echo "usage: $0 on | off" >&2
    exit 2
    ;;
esac