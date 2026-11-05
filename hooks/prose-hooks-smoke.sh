#!/usr/bin/env bash
# Smoke test for the prose hooks. Runs each hook script with sample hook input in a throwaway HOME and repo.
#
# Usage: prose-hooks-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

hooks=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

dash=$'\xE2\x80\x94'
home=$tmp/home
repo=$tmp/repo
plain=$tmp/plain
gone=$tmp/does-not-exist
mkdir -p "$home" "$plain" "$repo/.bf/conventions"
git init -q "$repo"
cat > "$repo/.bf/conventions/prose.md" <<'MD'
# Project prose

## Self-lint

PROJECT-OVERRIDE-ITEM

## Other
MD

# hook <script> <input json> [VAR=value...]: runs one hook with CLAUDE_PLUGIN_ROOT unset. Sets out and rc.
out= rc=0
hook() {
  local script=$1 input=$2; shift 2
  rc=0
  out=$(printf '%s' "$input" | env -u CLAUDE_PLUGIN_ROOT HOME="$home" GIT_CEILING_DIRECTORIES="$tmp" "$@" bash "$hooks/$script" 2>/dev/null) || rc=$?
}
input() { jq -cn --arg cwd "$1" '{cwd:$cwd}'; }

# SessionStart
hook prose-session-start.sh "$(input "$repo")" BF_PROSE_HOOK=off
eq "off switch output" "$out" ""; eq "off switch exit" "$rc" 0
hook prose-session-start.sh "$(input "$repo")"
eq "session start event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" SessionStart
eq "session start uses project override" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" "PROJECT-OVERRIDE-ITEM"
hook prose-session-start.sh "$(input "$plain")"
eq "session start plugin items" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c '^[1-8]\. ')" 8
hook prose-session-start.sh "not json"
eq "bad json output" "$out" ""; eq "bad json exit" "$rc" 0
hook prose-session-start.sh "$(input "$gone")"
eq "no lint result output" "$out" ""; eq "no lint result exit" "$rc" 0

[ "$fails" -eq 0 ]
