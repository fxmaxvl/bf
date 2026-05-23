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
    mkdir -p "$STATE_DIR"

    # Step 1: Migrate old-format (singleton) state.json BEFORE collision check.
    # Two-step write invariant: registry entry presence implies per-repo file should
    # exist; COLLISION treats either as authoritative (belt+suspenders).
    if [[ -f "$GLOBAL_STATE_FILE" ]]; then
      if jq -e 'has("active")' "$GLOBAL_STATE_FILE" >/dev/null 2>&1; then
        echo '{"entries":{}}' > "$GLOBAL_STATE_FILE"
        echo "bf:autopilot: migrated legacy state.json format" >&2
      fi
    fi

    # Step 2: Collision check against (now-migrated) state.
    if [[ "$FORCE" != "--force" ]]; then
      registry_hit=false
      repo_hit=false
      if [[ -f "$GLOBAL_STATE_FILE" ]]; then
        if jq -e --arg pid "$PROJECT_ID" '.entries[$pid] != null' "$GLOBAL_STATE_FILE" >/dev/null 2>&1; then
          registry_hit=true
        fi
      fi
      [[ -f "$REPO_STATE_FILE" ]] && repo_hit=true

      if [[ "$registry_hit" == "true" && "$repo_hit" == "true" ]]; then
        scope="registry+repo ($PROJECT_ID)"
      elif [[ "$registry_hit" == "true" ]]; then
        scope="registry ($PROJECT_ID)"
      elif [[ "$repo_hit" == "true" ]]; then
        scope="repo ($PROJECT_ID)"
      else
        scope=""
      fi

      if [[ -n "$scope" ]]; then
        echo "COLLISION:${scope}:${GLOBAL_STATE_FILE}"
        exit 1
      fi
    fi

    # Step 3: Upsert entries[PROJECT_ID] into global registry.
    started_at=$(date -u +%Y%m%dT%H%M%S)
    if [[ ! -f "$GLOBAL_STATE_FILE" ]]; then
      echo '{"entries":{}}' > "$GLOBAL_STATE_FILE"
    fi
    tmp=$(mktemp)
    jq --arg pid "$PROJECT_ID" --arg ts "$started_at" --arg root "$REPO_ROOT" \
      '.entries[$pid] = {started_at: $ts, repo_root: $root}' \
      "$GLOBAL_STATE_FILE" > "$tmp" && mv "$tmp" "$GLOBAL_STATE_FILE"

    # Step 4: Write per-repo file (per-repo lock; checked by stop.sh).
    jq -n --arg pid "$PROJECT_ID" --arg ts "$started_at" --arg root "$REPO_ROOT" \
      '{active: true, project_id: $pid, started_at: $ts, repo_root: $root}' > "$REPO_STATE_FILE"

    add_hook "$CLAUDE_SETTINGS"

    echo "bf:autopilot hook installed."
    echo "global registry: $GLOBAL_STATE_FILE"
    echo "repo state:      $REPO_STATE_FILE"
    echo
    echo "To stop autopilot:"
    echo "  - type anything at the prompt (UserPromptSubmit hook wipes state)"
    echo "  - close/reopen Claude Code (SessionStart hook wipes state)"
    echo "  - manual:  bash $SKILL_DIR/hooks/install.sh off"
    ;;
  off)
    # jq-delete entries[PROJECT_ID] from global registry; preserve file as {"entries":{...}}.
    # See install.sh on for the two-step write invariant (registry entry + per-repo file).
    if [[ -f "$GLOBAL_STATE_FILE" ]]; then
      if jq -e 'has("entries")' "$GLOBAL_STATE_FILE" >/dev/null 2>&1; then
        tmp=$(mktemp)
        jq --arg pid "$PROJECT_ID" 'del(.entries[$pid])' \
          "$GLOBAL_STATE_FILE" > "$tmp" && mv "$tmp" "$GLOBAL_STATE_FILE"
      fi
    fi
    rm -f "$REPO_STATE_FILE"
    remove_hook "$CLAUDE_SETTINGS"
    echo "bf:autopilot hook removed."
    ;;
  *)
    echo "usage: $0 on | off" >&2
    exit 2
    ;;
esac