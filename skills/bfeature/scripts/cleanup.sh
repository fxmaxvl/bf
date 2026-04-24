#!/usr/bin/env bash
# cleanup.sh — Remove ephemeral bfeature artifacts and build-state.json.
#
# Reads state via state-ops.sh to resolve paths, then deletes:
#   - qa.md, design-report.md, impl-report.md  (ephemeral handoff files)
#   - build-state.json                          (last, so state survives partial failures)
#
# Persistent artifacts (spec, plan, todo, backlog, deployment) are kept.
#
# Usage:
#   bash ~/.claude/skills/bfeature/scripts/cleanup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load state
state_json=$(bash "$SCRIPT_DIR/state-ops.sh")
if [ $? -ne 0 ]; then
  echo "Error: could not read build state" >&2
  exit 1
fi

artifacts_dir=$(echo "$state_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['artifacts_dir'])")
qa=$(echo "$state_json"           | python3 -c "import json,sys; print(json.load(sys.stdin)['paths']['qa'])")
design=$(echo "$state_json"       | python3 -c "import json,sys; print(json.load(sys.stdin)['paths']['design_report'])")
impl=$(echo "$state_json"         | python3 -c "import json,sys; print(json.load(sys.stdin)['paths']['impl_report'])")
state_file="$artifacts_dir/build-state.json"

deleted=()

for f in "$qa" "$design" "$impl"; do
  if [ -f "$f" ]; then
    rm "$f"
    deleted+=("$(basename "$f")")
  fi
done

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
