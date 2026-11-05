#!/usr/bin/env bash
# UserPromptSubmit hook: tell the model about the lint result of its last reply, once.
#
# Usage: hook input JSON on stdin
# Output: hookSpecificOutput JSON with one line, "last reply: <summary>", then the record is deleted.
#         No output when there is no record.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/prose-lib.sh"

prose_off && exit 0
prose_read_input

sid=$(prose_field .session_id)
[ -n "$sid" ] || exit 0
line=$(prose_record_take "$sid")
[ -n "$line" ] || exit 0
prose_context UserPromptSubmit "last reply: $line"
