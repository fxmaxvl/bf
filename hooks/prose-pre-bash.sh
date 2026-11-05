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

# The tokenizer reads quotes and escapes and never evaluates the text. It prints the plain quoted values
# of the handled flags, separated by a blank line. A value made only of quoted parts and backslash escapes,
# such as 'don'\''t', is linted. A value is skipped when it has a bare part, is glued to a
# short flag (such as -m"x"), supplied by -F or --body-file, or holds a heredoc, a command substitution
# or a backtick. A value in the form --flag="value" is linted.
values=$(printf '%s\n' "$cmd" | awk '
function ok(v) { return v != "" && !index(v, "<<") && !index(v, "$(") && !index(v, "`") }
function add(v) { if (ok(v)) out = out (out == "" ? "" : "\n\n") v }
function takes(ctx, flag) {
  if (ctx == "commit") return flag == "-m" || flag == "--message"
  if (ctx == "pr") return flag == "--body" || flag == "-b" || flag == "--title"
  if (ctx == "fin") return flag == "--commit-msg" || flag == "--pr-title" || flag == "--pr-body"
  return 0
}
function reset() { ctx = ""; want = ""; p1 = ""; p2 = ""; g = 0 }
function endtok(   v, flag) {
  if (!intok) return
  intok = 0
  whole = (nseg >= 1 && !bare)
  glued = (nseg == 1 && !tail && pre ~ /^--[A-Za-z-]+=$/)
  if (want == "take") { want = ""; if (whole) add(text); p2 = p1; p1 = ""; return }
  if (want == "skip") { want = ""; p2 = p1; p1 = ""; return }
  if (text ~ /(^|\/)finalize-git\.sh$/) { ctx = "fin"; p2 = p1; p1 = text; return }
  if (nseg == 0) {
    if (text == "git") g = 1
    else if (g && ctx == "" && (text == "-C" || text == "-c")) want = "skip"
    else if (g && ctx == "" && text == "commit") { ctx = "commit"; g = 0 }
    else if (g && ctx == "" && text !~ /^-/) g = 0
    else if (text == "create" && p1 == "pr" && p2 == "gh") ctx = "pr"
    else if (ctx == "commit") {
      if (takes(ctx, text) || text ~ /^-[A-Za-z]+m$/) want = "take"
      else if (text == "-F" || text == "--file") want = "skip"
    } else if (ctx == "pr") {
      if (takes(ctx, text)) want = "take"
      else if (text == "--body-file" || text == "-F") want = "skip"
    } else if (ctx == "fin") {
      if (takes(ctx, text)) want = "take"
    }
    p2 = p1; p1 = text
  } else {
    if (glued) { flag = substr(pre, 1, length(pre) - 1); if (takes(ctx, flag)) add(substr(text, length(pre) + 1)) }
    p2 = p1; p1 = ""
  }
}
BEGIN { sq = sprintf("%c", 39); dq = "\""; bs = "\\"; q = "" }
{ cmd = cmd (NR > 1 ? "\n" : "") $0 }
END {
  n = length(cmd)
  for (i = 1; i <= n; i++) {
    c = substr(cmd, i, 1)
    if (q != "") {
      if (c == q) { q = ""; continue }
      if (q == dq && c == bs) {
        d = substr(cmd, i + 1, 1)
        if (d == dq || d == bs || d == "$" || d == "`") { text = text d; i++; continue }
      }
      text = text c
      continue
    }
    if (c == sq || c == dq) {
      if (!intok) { intok = 1; text = ""; nseg = 0; tail = 0; pre = ""; bare = 0 }
      nseg++
      if (nseg == 1) pre = text
      q = c
      continue
    }
    if (c == " " || c == "\t") { endtok(); continue }
    if (c == "\n" || c == ";" || c == "&" || c == "|" || c == "(" || c == ")") { endtok(); reset(); continue }
    if (c == "#" && !intok) { while (i < n && substr(cmd, i + 1, 1) != "\n") i++; continue }
    if (!intok) { intok = 1; text = ""; nseg = 0; tail = 0; pre = ""; bare = 0 }
    if (c == bs) { c = substr(cmd, i + 1, 1); i++ } else bare = 1
    text = text c
    if (nseg >= 1) tail = 1
  }
  endtok()
  if (q == "") print out
}')
[ -n "$values" ] || exit 0

cwd=$(prose_cwd)
rc=0
out=$(printf '%s\n' "$values" | prose_lint "$cwd" commit) || rc=$?
[ "$rc" -eq 1 ] || exit 0

prose_context PreToolUse "Prose lint found hard markers in the commit or PR text of this command: $(jq -r .hard_summary <<<"$out"). The command already ran. To fix the text, use gh pr edit, or git commit --amend after you check that the commit is not pushed."
