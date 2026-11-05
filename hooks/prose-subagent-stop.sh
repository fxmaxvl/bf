#!/usr/bin/env bash
# SubagentStop hook: ask a sub-agent to fix hard prose markers in its final text. This is the only prose
# hook that can block.
#
# Usage: hook input JSON on stdin
# Output: {"decision":"block","reason":...} when the final text has a hard marker and the resolved prose.md
#         has a prose-lint block. No output otherwise, including when stop_hook_active is true.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/prose-lib.sh"

prose_off && exit 0
prose_read_input
[ "$(prose_field .stop_hook_active)" != true ] || exit 0

rc=0
out=$(printf '%s\n' "$(prose_field .last_assistant_message)" | prose_lint "$(prose_cwd)" chat) || rc=$?
[ "$rc" -eq 1 ] || exit 0
[ "$(jq -r .rules_block <<<"$out")" = true ] || exit 0

jq -n --arg s "$(jq -r .summary <<<"$out")" \
  '{decision:"block", reason:("Your final text has hard prose markers: " + $s + ". Remove the em dashes, semicolons and contractions from your final text, then return it again.")}'
