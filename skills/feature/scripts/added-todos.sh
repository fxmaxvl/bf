#!/usr/bin/env bash
# List TODO comments this branch added, so the whole branch diff never enters the conversation.
#
# Usage: added-todos.sh <base> [<file>...]
#   <base>  the remote-tracking ref changed-packages.sh reports as `base` — never a bare local
#           branch, which can sit behind its remote and attribute upstream TODOs to this branch
#   <file>  optional changed_files to restrict the search to
# Output: JSON array [{file, line, text, context}]
#   line     1-based line number in the file at HEAD
#   text     the added line, trimmed
#   context  up to 2 lines above and below, from the file at HEAD
# Matching is case-insensitive on `todo`. Errors: {"error":...} + exit 1.
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }
command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"
[ $# -ge 1 ] || die usage "added-todos.sh <base> [<file>...]"
base=$1; shift
git rev-parse --verify --quiet "$base" >/dev/null || die bad_base "$base"

# -U0 leaves only changed lines, so each @@ header's new-side start is the first added line.
hits=$(git -c core.quotePath=false diff -U0 "$base"...HEAD -- "$@" 2>/dev/null | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^\+\+\+ /    { file = ""; next }
  /^@@/ {
    split($3, a, ","); n = substr(a[1], 2) + 0; next
  }
  /^\+/ {
    if (file != "" && tolower($0) ~ /todo/) { printf "%s\t%d\t%s\n", file, n, substr($0, 2) }
    n++
  }')

[ -n "$hits" ] || { echo '[]'; exit 0; }

while IFS=$'\t' read -r file line text; do
  from=$(( line > 2 ? line - 2 : 1 ))
  context=$(git show "HEAD:$file" 2>/dev/null | sed -n "${from},$(( line + 2 ))p")
  jq -cn --arg f "$file" --argjson l "$line" --arg t "$text" --arg c "$context" \
    '{file:$f, line:$l, text:($t|gsub("^\\s+|\\s+$";"")), context:$c}'
done <<< "$hits" | jq -cs .
