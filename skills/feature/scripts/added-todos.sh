#!/usr/bin/env bash
# List TODO comments this branch added, so the whole branch diff never enters the conversation.
#
# Usage: added-todos.sh <base> [<file>...]
#   <base>  the remote-tracking ref changed-packages.sh reports as `base` — never a bare local
#           branch, which can sit behind its remote and attribute upstream TODOs to this branch
#   <file>  optional changed_files to restrict the search to; none means the whole branch diff
# Output: JSON array [{file, line, text, context}]
#   line     1-based line number in the file at HEAD
#   text     the added line, trimmed
#   context  up to 2 lines above and below, from the file at HEAD
# Matching is case-insensitive on `todo` as a standalone word: `TODO:` and `# todo x` match,
# `todos`, `added-todos.sh` and `mastodon` do not.
# Errors: {"error":...,"detail":...} + exit 1 — usage, bad_base, diff_failed (no merge base,
# shallow clone), jq_missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
die() { jq -cn --arg e "$1" --arg d "${2:-}" '{error:$e, detail:$d}'; exit 1; }
[ $# -ge 1 ] || die usage "added-todos.sh <base> [<file>...]"
base=$1; shift
git rev-parse --verify --quiet "$base" >/dev/null || die bad_base "$base"

err=$(mktemp)
trap 'rm -f "$err"' EXIT
# Explicit flags make the parse independent of user diff config (color, prefixes, quoting).
diff=$(git -c core.quotePath=false diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ \
  -U0 "$base"...HEAD -- "$@" 2>"$err") || die diff_failed "$(head -n1 "$err")"

# -U0 leaves only changed lines, so each @@ header's new-side start is the first added line.
# `+++ ` is a file header only before the first hunk; inside a hunk every `+` line is content.
hits=$(printf '%s\n' "$diff" | awk '
  /^diff --git / { in_header = 1; file = ""; next }
  /^@@/ {
    in_header = 0
    split($3, a, ","); n = substr(a[1], 2) + 0; next
  }
  in_header && /^\+\+\+ b\// { file = substr($0, 7); next }
  in_header { next }
  /^\+/ {
    if (file != "" && tolower(substr($0, 2)) ~ /(^|[^a-z0-9_-])todo([^a-z0-9_-]|$)/) {
      printf "%s\t%d\t%s\n", file, n, substr($0, 2)
    }
    n++
  }')

[ -n "$hits" ] || { echo '[]'; exit 0; }

while IFS=$'\t' read -r file line text; do
  from=$(( line > 2 ? line - 2 : 1 ))
  context=$({ git show "HEAD:$file" 2>/dev/null || true; } | sed -n "${from},$(( line + 2 ))p")
  jq -cn --arg f "$file" --argjson l "$line" --arg t "$text" --arg c "$context" \
    '{file:$f, line:$l, text:($t|gsub("^\\s+|\\s+$";"")), context:$c}'
done <<< "$hits" | jq -cs .
