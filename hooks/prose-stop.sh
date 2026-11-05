#!/usr/bin/env bash
# Stop hook: lint the last reply and record the result for the next prompt. It sends no feedback and
# never blocks, so it adds no model turn.
#
# Usage: hook input JSON on stdin
# Output: none. A hard marker or a long reply writes one summary line to the record. Every Stop clears the old record first.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/prose-lib.sh"

prose_off && exit 0
prose_read_input

sid=$(prose_field .session_id)
[ -n "$sid" ] || exit 0

# The old record goes first, so a Stop with no lint result never leaves the record of an older reply.
prose_record_clear "$sid"

rc=0
out=$(printf '%s\n' "$(prose_field .last_assistant_message)" | prose_lint "$(prose_cwd)" chat) || rc=$?
[ "$rc" -ne 2 ] || exit 0

# A long reply is the one trigger that is not a hard marker, and only this hook reads it.
if [ "$rc" -eq 1 ] || [ "$(jq -r .long_reply <<<"$out")" = true ]; then
  prose_record_write "$sid" "$(jq -r .summary <<<"$out")"
fi
