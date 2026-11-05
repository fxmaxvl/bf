#!/usr/bin/env bash
# PreToolUse (Bash) hook: lint the plain quoted commit and PR text of git commit, gh pr create and
# finalize-git.sh. This hook runs on every Bash call, so a case on the raw input comes before any jq call.
#
# Usage: hook input JSON on stdin
# Output: hookSpecificOutput JSON with a short note when the text has a hard marker. The note never sets
#         permissionDecision, because "allow" would skip the user's Bash permission prompt.
#         No output otherwise, including when a value is skipped or the parse fails.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/prose-lib.sh"

prose_off && exit 0
prose_read_raw
case $PROSE_INPUT in
  *"git "*commit*|*"gh pr create"*|*finalize-git.sh*) ;;
  *) exit 0 ;;
esac
prose_validate_input

cmd=$(prose_field .tool_input.command)
[ -n "$cmd" ] || exit 0

values=$(prose_commit_values "$cmd")
[ -n "$values" ] || exit 0

cwd=$(prose_cwd)
rc=0
out=$(printf '%s\n' "$values" | prose_lint "$cwd" commit) || rc=$?
[ "$rc" -eq 1 ] || exit 0

prose_context PreToolUse "Prose lint found hard markers in the commit or PR text of this command: $(jq -r .hard_summary <<<"$out"). The command already ran. To fix the text, use gh pr edit, or git commit --amend after you check that the commit is not pushed."
