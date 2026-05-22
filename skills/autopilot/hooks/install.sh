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

PROJECT_ID=$(git config --get remote.origin.url 2>/dev/null \
  | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$REPO_ROOT")

GLOBAL_STATE_FILE="$STATE_DIR/state.json"
REPO_STATE_FILE="$STATE_DIR/${PROJECT_ID}.json"

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
    | .permissions = (.permissions // {})
    | (if (.permissions | has("__bf_autopilot_prev_defaultMode"))
       then .
       else .permissions.__bf_autopilot_prev_defaultMode = (.permissions.defaultMode // "__absent__")
       end)
    | .permissions.defaultMode = "bypassPermissions"
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
    | (if ((.permissions.__bf_autopilot_prev_defaultMode // "__absent__") == "__absent__")
       then del(.permissions.defaultMode)
       else .permissions.defaultMode = .permissions.__bf_autopilot_prev_defaultMode
       end)
    | del(.permissions.__bf_autopilot_prev_defaultMode)
    | if (.permissions // {}) == {} then del(.permissions) else . end
  ' "$path" > "$tmp" && mv "$tmp" "$path"
}

case "$ACTION" in
  on)
    FORCE="${2:-}"
    if [[ "$FORCE" != "--force" ]]; then
      collisions=()
      [[ -f "$GLOBAL_STATE_FILE" ]] && collisions+=("global")
      [[ -f "$REPO_STATE_FILE" ]] && collisions+=("repo ($PROJECT_ID)")
      if [[ ${#collisions[@]} -gt 0 ]]; then
        scope=$(IFS=" and "; echo "${collisions[*]}")
        echo "COLLISION:${scope}:${GLOBAL_STATE_FILE}"
        exit 1
      fi
    fi

    mkdir -p "$STATE_DIR"
    started_at=$(date -u +%Y%m%dT%H%M%S)
    jq -n --arg pid "$PROJECT_ID" --arg ts "$started_at" \
      '{active: true, project_id: $pid, started_at: $ts}' > "$GLOBAL_STATE_FILE"
    jq -n --arg pid "$PROJECT_ID" --arg ts "$started_at" \
      '{active: true, project_id: $pid, started_at: $ts}' > "$REPO_STATE_FILE"

    add_hook "$CLAUDE_SETTINGS"

    echo "bf:autopilot hook installed."
    echo "global state: $GLOBAL_STATE_FILE"
    echo "repo state:   $REPO_STATE_FILE"
    echo
    echo "To stop autopilot:"
    echo "  - type anything at the prompt (UserPromptSubmit hook wipes state)"
    echo "  - close/reopen Claude Code (SessionStart hook wipes state)"
    echo "  - manual:  bash $SKILL_DIR/hooks/install.sh off"
    ;;
  off)
    rm -f "$GLOBAL_STATE_FILE" "$REPO_STATE_FILE"
    remove_hook "$CLAUDE_SETTINGS"
    echo "bf:autopilot hook removed."
    ;;
  *)
    echo "usage: $0 on | off" >&2
    exit 2
    ;;
esac