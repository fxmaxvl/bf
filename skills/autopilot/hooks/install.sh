#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-}"

SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
# shellcheck source=hooks/lib.sh
source "$SKILL_DIR/hooks/lib.sh"
STATE_DIR=$(_state_dir)
PROJECT_ID=$(_derive_project_id)

GLOBAL_STATE_FILE="$STATE_DIR/state.json"
REPO_STATE_FILE=$(_state_file)

CLAUDE_SETTINGS="$REPO_ROOT/.claude/settings.local.json"

# Identifies an autopilot hook entry. The `__tag` key is not durable — the harness
# rewrites settings.local.json (it grows permissions.allow on its own) and drops keys
# it does not recognise, which left untagged entries that `off` could not remove and
# `on` kept appending to. So match the command path too: that is self-describing and
# survives any rewrite. The suffix is deliberately version-independent, so one `off`
# also clears entries stranded by earlier releases.
# shellcheck disable=SC2016  # $tag/$suffix are jq variables — they must not expand in shell
BF_ENTRY_DEF='def bf_entry($tag; $suffix):
    ((.__tag // "") == $tag)
    or (any(.hooks[]?; ((.command // "") | endswith($suffix))));'

# The hooks this skill installs: event, entry tag, script name and matcher. add_hook and
# remove_hook both read this table.
HOOK_TABLE='[
  {"event": "Stop", "tag": "bf-autopilot-stop", "script": "stop.sh", "matcher": ""},
  {"event": "SessionStart", "tag": "bf-autopilot-cleanup", "script": "session-start-cleanup.sh", "matcher": "startup|resume|clear"},
  {"event": "UserPromptSubmit", "tag": "bf-autopilot-user-cleanup", "script": "user-prompt-cleanup.sh", "matcher": ""}
]'
while read -r script; do chmod +x "$SKILL_DIR/hooks/$script"; done < <(jq -r '.[].script' <<<"$HOOK_TABLE")

add_hook() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  [[ -f "$path" ]] || echo '{}' > "$path"
  local tmp
  tmp=$(mktemp)
  jq --arg dir "$SKILL_DIR/hooks" --argjson table "$HOOK_TABLE" '
    '"$BF_ENTRY_DEF"'
    .hooks = (.hooks // {}) |
    reduce $table[] as $h (.;
      .hooks[$h.event] = (
        [(.hooks[$h.event] // [])[] | select(bf_entry($h.tag; "/skills/autopilot/hooks/" + $h.script) | not)] +
        [{ __tag: $h.tag,
           matcher: $h.matcher,
           hooks: [{ type: "command", command: ($dir + "/" + $h.script) }] }]
      )
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
  jq --argjson table "$HOOK_TABLE" '
    '"$BF_ENTRY_DEF"'
    reduce $table[] as $h (.;
      (if .hooks[$h.event] then
        .hooks[$h.event] |= [.[] | select(bf_entry($h.tag; "/skills/autopilot/hooks/" + $h.script) | not)]
      else . end)
      | if (.hooks[$h.event] // []) | length == 0 then del(.hooks[$h.event]) else . end
    )
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
    # Two-step write invariant: registry entry presence implies per-repo file should
    # exist; COLLISION treats either as authoritative (belt+suspenders).
    started_at=$(date -u +%Y%m%dT%H%M%S)
    if [[ ! -f "$GLOBAL_STATE_FILE" ]]; then
      echo '{"entries":{}}' > "$GLOBAL_STATE_FILE"
    fi
    tmp=$(mktemp)
    jq --arg pid "$PROJECT_ID" --arg ts "$started_at" --arg root "$REPO_ROOT" \
      '.entries[$pid] = {started_at: $ts, repo_root: $root}' \
      "$GLOBAL_STATE_FILE" > "$tmp" && mv "$tmp" "$GLOBAL_STATE_FILE"

    # Step 4: Write per-repo file (per-repo lock; checked by stop.sh).
    # The lead session and its process own the run. The hooks read them, see lib.sh. Both come from
    # the environment of the session that runs this command. When one is empty, the owner check
    # matches any session or the lead counts as ended, so the second-session guards degrade.
    if [[ -z "${CLAUDE_CODE_SESSION_ID:-}" || -z "${CLAUDE_PID:-}" ]]; then
      echo "bf:autopilot: warning: CLAUDE_CODE_SESSION_ID or CLAUDE_PID is empty. Another session can end or share this run." >&2
    fi
    lead_pid="${CLAUDE_PID:-}"
    lead_started=""
    [[ -z "$lead_pid" ]] || lead_started=$(ps -p "$lead_pid" -o lstart= 2>/dev/null || true)
    jq -n --arg pid "$PROJECT_ID" --arg ts "$started_at" --arg root "$REPO_ROOT" \
      --arg sid "${CLAUDE_CODE_SESSION_ID:-}" --arg lpid "$lead_pid" --arg lstart "$lead_started" \
      '{active: true, project_id: $pid, started_at: $ts, repo_root: $root,
        session_id: $sid, lead_pid: $lpid, lead_started: $lstart}' > "$REPO_STATE_FILE"

    add_hook "$CLAUDE_SETTINGS"

    echo "bf:autopilot hook installed."
    echo "global registry: $GLOBAL_STATE_FILE"
    echo "repo state:      $REPO_STATE_FILE"
    echo
    echo "To stop autopilot:"
    echo "  - type one word: stop, cancel, abort, quit or exit"
    echo "  - or ask in your own words (\"please stop autopilot\"), and the model ends the run"
    echo "  - resume or clear the lead session, or start a new session after the lead exits (SessionStart hook wipes state). Compaction keeps the run."
    echo "  - a second session that starts while the lead runs leaves the run alone and gets a warning"
    echo "  - manual:  bash $SKILL_DIR/hooks/install.sh off"
    ;;
  off)
    # Remove entries[PROJECT_ID] from global registry; delete the file when empty.
    # See the two-step write invariant comment in 'on' Step 3.
    if [[ -f "$GLOBAL_STATE_FILE" ]]; then
      if jq -e 'has("entries")' "$GLOBAL_STATE_FILE" >/dev/null 2>&1; then
        tmp=$(mktemp)
        jq --arg pid "$PROJECT_ID" 'del(.entries[$pid])' \
          "$GLOBAL_STATE_FILE" > "$tmp" && mv "$tmp" "$GLOBAL_STATE_FILE"
        # Delete the global file once all sessions are gone.
        if jq -e '.entries == {}' "$GLOBAL_STATE_FILE" >/dev/null 2>&1; then
          rm -f "$GLOBAL_STATE_FILE"
        fi
      else
        rm -f "$GLOBAL_STATE_FILE"
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