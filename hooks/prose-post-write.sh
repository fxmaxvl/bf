#!/usr/bin/env bash
# PostToolUse (Write|Edit) hook: lint the new text of a written file for hard prose markers.
#
# Usage: hook input JSON on stdin
# Output: hookSpecificOutput JSON with a short note when the new text has a hard marker. Never blocks.
#         No output otherwise.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/prose-lib.sh"

prose_off && exit 0
prose_read_input

tool=$(prose_field .tool_name)
path=$(prose_field .tool_input.file_path)
case $tool in
  Write) text=$(prose_field .tool_input.content) ;;
  Edit) text=$(prose_field .tool_input.new_string) ;;
  *) exit 0 ;;
esac
[ -n "$path" ] && [ -n "$text" ] || exit 0

# The lint owns the list of supported files. An unsupported path ends the hook.
cls=$(prose_classify "$path") || exit 0
read -r mode ext <<<"$cls"

cwd=$(prose_cwd)

# The skip list matches path segments relative to the root of the repo that holds the file, so a parent
# directory such as ~/work/conventions/ does not cause a skip. A file outside any repo has no repo root, so
# the list matches the full path. git gives the prefix, so a path through a symlink still matches.
case ${path##*/} in SKILL.md|CLAUDE.md|AGENTS.md) exit 0 ;; esac
if prefix=$(git -C "$(dirname "$path")" rev-parse --show-prefix 2>/dev/null); then
  rel=$prefix${path##*/}
else
  rel=$path
fi
case "/$rel" in */conventions/*|*/agents/*|*/references/*|*/.claude/*) exit 0 ;; esac

args=()
[ -z "$ext" ] || args+=(--ext "$ext")
rc=0
out=$(printf '%s\n' "$text" | prose_lint "$cwd" "$mode" ${args[@]+"${args[@]}"}) || rc=$?
[ "$rc" -eq 1 ] || exit 0

note="Prose lint found hard markers in the new text of $path: $(jq -r .hard_summary <<<"$out"). Rewrite them under the prose convention."
if [ "$tool" = Edit ]; then
  note="$note An edit is linted as a fragment, so text inside a code fence can give a false positive."
fi
prose_context PostToolUse "$note"
