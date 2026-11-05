#!/usr/bin/env bash
# SessionStart (compact) hook: bring the prose rules back after context compaction.
#
# Usage: hook input JSON on stdin
# Output: hookSpecificOutput JSON with the Self-lint section of the resolved prose.md as additionalContext.
#         No output when BF_PROSE_HOOK=off or the rules cannot be read.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/prose-lib.sh"

prose_off && exit 0
prose_read_input
digest=$(prose_digest "$(prose_cwd)") || exit 0
[ -n "$digest" ] || exit 0
prose_context SessionStart "$digest"
