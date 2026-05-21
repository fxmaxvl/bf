#!/usr/bin/env bash
# cleanup.sh — Remove ephemeral feature artifacts and build-state.json.
#
# Reads state via state-ops.sh to resolve paths, then deletes:
#   - <prefix>-temp.md  (ephemeral blocks: qa, design-report, impl-report, complexity-report)
#   - build-state.json     (last, so state survives partial failures)
#
# Persistent artifacts in <prefix>-session-log.md (spec, plan, todo, backlog, deployment) are kept.
#
# Usage:
#   bash ~/.claude/skills/feature/scripts/cleanup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load state
state_json=$(bash "$SCRIPT_DIR/state-ops.sh")
if [ $? -ne 0 ]; then
  echo "Error: could not read build state" >&2
  exit 1
fi

artifacts_dir=$(echo "$state_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['artifacts_dir'])")
temp=$(echo "$state_json"          | python3 -c "import json,sys; print(json.load(sys.stdin)['paths']['temp'])")
state_file="$artifacts_dir/build-state.json"

deleted=()

if [ -f "$temp" ]; then
  rm "$temp"
  deleted+=("$(basename "$temp")")
fi

# Delete state last so partial failures leave state intact
if [ -f "$state_file" ]; then
  rm "$state_file"
  deleted+=("build-state.json")
fi

if [ ${#deleted[@]} -eq 0 ]; then
  echo "Nothing to clean up."
else
  echo "Deleted: ${deleted[*]}"
fi
