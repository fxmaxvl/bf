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


# PostToolUse
mkdir -p "$tmp/conventions"
repo2=$tmp/conventions/repo2
git init -q "$repo2"
write_in() { jq -cn --arg cwd "$1" --arg tool "$2" --arg p "$3" --arg k "$4" --arg t "$5" \
  '{cwd:$cwd, tool_name:$tool, tool_input:({file_path:$p} + {($k):$t})}'; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out"; }

hook prose-post-write.sh "$(write_in "$repo" Write "$repo/README.md" content "A${dash}B.")"
eq "post-write event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" PostToolUse
eq "post-write md em dash" "$(ctx | grep -c '1 em dash')" 1
eq "post-write note names the path" "$(ctx | grep -c "$repo/README.md")" 1
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/skills/x/SKILL.md" content "A${dash}B.")"
eq "post-write SKILL.md skipped" "$out" ""
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/.bf/conventions/prose.md" content "A${dash}B.")"
eq "post-write conventions skipped" "$out" ""
hook prose-post-write.sh "$(write_in "$repo2" Write "$repo2/README.md" content "A${dash}B.")"
eq "post-write parent conventions dir not skipped" "$(ctx | grep -c '1 em dash')" 1
hook prose-post-write.sh "$(write_in "$repo" Edit "$repo/README.md" new_string "clean text.")"
eq "post-write edit clean new_string" "$out" ""
hook prose-post-write.sh "$(write_in "$repo" Edit "$repo/README.md" new_string "one; two")"
eq "post-write edit hit" "$(ctx | grep -c '1 semicolon')" 1
eq "post-write edit fence warning" "$(ctx | grep -c 'code fence')" 1
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/a.ts" content $'  #count = 0;\nconst x = 1;')"
eq "post-write ts private field" "$out" ""
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/a.sh" content $'echo hi\n# one; two')"
eq "post-write sh comment hit" "$(ctx | grep -c '1 semicolon')" 1
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/a.json" content "A${dash}B")"
eq "post-write json skipped" "$out" ""
hook prose-post-write.sh "$(write_in "$gone" Write "$gone/README.md" content "A${dash}B.")"
eq "post-write no lint result output" "$out" ""; eq "post-write no lint result exit" "$rc" 0
hook prose-post-write.sh "$(write_in "$repo" Read "$repo/README.md" content "A${dash}B.")"
eq "post-write other tool" "$out" ""

[ "$fails" -eq 0 ]
