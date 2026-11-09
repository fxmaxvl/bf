#!/usr/bin/env bash
# Smoke test for remote-state-pre-bash.sh: which Bash commands get the fetch-first reminder.
#
# Usage: remote-state-hook-smoke.sh
# Output: one PASS or FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -uo pipefail

hook="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/remote-state-pre-bash.sh"
fails=0

run() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | env "${@:2}" bash "$hook"; }
fires() {
  local out; out=$(run "$@")
  if jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | test("git fetch"))
            and (.hookSpecificOutput | has("permissionDecision") | not)' <<< "$out" >/dev/null 2>&1
  then echo "PASS fires: $1"; else echo "FAIL fires: $1: got [$out]"; fails=$((fails+1)); fi
}
quiet() {
  local out; out=$(run "$@")
  if [ -z "$out" ]; then echo "PASS quiet: $1 ${*:2}"; else echo "FAIL quiet: $1: got [$out]"; fails=$((fails+1)); fi
}

fires 'git push'
fires 'git push -u origin chore/x'
fires 'git -C /tmp/repo push origin HEAD'
fires 'git add a && git push'
fires 'gh pr edit 12 --body-file b.md'
fires 'gh pr merge 12 --squash'
quiet 'git status'
quiet 'git commit -m "push the fix"'
quiet 'gh pr view 12 --json state'
quiet 'gh pr create --title t'
quiet 'bash skills/feature/scripts/finalize-git.sh --push'
quiet 'git push' BF_REMOTE_HOOK=off
out=$(printf 'not json git push' | bash "$hook"); rc=$?
if [ -z "$out" ] && [ "$rc" = 0 ]; then echo "PASS quiet: input that is not JSON"; else echo "FAIL quiet: input that is not JSON: rc=$rc [$out]"; fails=$((fails+1)); fi

[ "$fails" = 0 ]
