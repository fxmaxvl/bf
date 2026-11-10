#!/usr/bin/env bash
# PreToolUse (Bash) hook: before git push, gh pr edit or gh pr merge, remind the model to fetch and check
# the PR state. A push to a merged or closed PR strands its commits. This hook runs on every Bash call,
# so a case on the raw input comes before any jq call. The case is only a cheap prefilter and accepts
# every input the two predicates below accept. The predicates decide.
#
# Usage: hook input JSON on stdin
# Output: hookSpecificOutput JSON with the reminder when the command pushes, or edits or merges a PR.
#         It never sets permissionDecision, because "allow" would skip the user's Bash permission prompt.
#         No output otherwise, when the parse fails, or when BF_REMOTE_HOOK=off.
# Limits: git options before the subcommand may carry a value: git -C /dir push, git -C "/a b" push,
#         git -c 'k=v w' push. Any whitespace, tabs included, may separate the words. A command that only
#         quotes the text "git push", such as an echo or a commit message, also fires. The reminder is
#         cheap, so the hook accepts that.
set -uo pipefail

[ "${BF_REMOTE_HOOK:-}" = off ] && exit 0
input=$(cat)
case $input in
  *push*|*gh*pr*) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

# Both predicates need the word to start the command or follow a character that cannot belong to a word,
# so git commit -m "push" and my-git push do not match.
start='(^|[^[:alnum:]_.-])'
sq="'"
opt_value="(\"[^\"]*\"|${sq}[^${sq}]*${sq}|[^-[:space:]][^[:space:]]*)"
is_git_push() {
  printf '%s' "$cmd" | grep -Eq "${start}git([[:space:]]+-[^[:space:]]+([[:space:]]+${opt_value})?)*[[:space:]]+push([[:space:]]|\$)"
}
is_gh_pr_change() {
  printf '%s' "$cmd" | grep -Eq "${start}gh[[:space:]]+pr[[:space:]]+(edit|merge)([[:space:]]|\$)"
}
is_git_push || is_gh_pr_change || exit 0

jq -n --arg t "This command pushes or changes a PR. First run git fetch, then check the PR state with gh pr list --head <branch> --state all --json number,state,headRefOid. Do not push to a MERGED or CLOSED PR whose headRefOid is in this branch's history, because those commits never reach the base branch." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$t}}'
