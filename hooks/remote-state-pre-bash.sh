#!/usr/bin/env bash
# PreToolUse (Bash) hook: before git push, gh pr edit or gh pr merge, remind the model to fetch and check
# the PR state. A push to a merged or closed PR strands its commits. This hook runs on every Bash call,
# so a case on the raw input comes before any jq call.
#
# Usage: hook input JSON on stdin
# Output: hookSpecificOutput JSON with the reminder when the command pushes, or edits or merges a PR.
#         It never sets permissionDecision, because "allow" would skip the user's Bash permission prompt.
#         No output otherwise, when the parse fails, or when BF_REMOTE_HOOK=off.
set -uo pipefail

[ "${BF_REMOTE_HOOK:-}" = off ] && exit 0
input=$(cat)
case $input in
  *"git "*push*|*"gh pr edit"*|*"gh pr merge"*) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

# git options before the subcommand (git -C <dir> push) still count, but git commit -m "push" does not.
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_.-])(git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+(edit|merge))([[:space:]]|$)' || exit 0

jq -n --arg t "This command pushes or changes a PR. First run git fetch, then check the PR state with gh pr list --head <branch> --state all --json number,state,headRefOid. Do not push to a MERGED or CLOSED PR whose headRefOid is in this branch's history, because those commits never reach the base branch." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$t}}'
