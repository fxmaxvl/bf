#!/usr/bin/env bash
# Resolve the scope of a change to assess. Emits one JSON object.
#
# Usage: scope.sh [--with-diff] [--with-untracked] [target]
#   target empty      → uncommitted changes; falls back to branch-vs-base when the tree is clean
#   target "branch"   → current branch vs merge-base with origin/HEAD
#   target <sha|range>→ that commit or range
#   target <paths...> → git diff limited to those paths
#
#   --with-diff       → append three keys after "files", leaving every existing key and its
#                       position untouched:
#                         diff_file             path to a temp file holding the raw diff body
#                         whitespace_only_files files with no hunk left under `git diff -w` — which
#                                               also catches binaries, pure renames and mode-only
#                                               changes, since none of those produces a hunk either
#                         hunks                 [{file,index,line,added,removed}] — `line` is the
#                                               1-based line of the `@@` header inside diff_file,
#                                               so a caller reads header text out of the file
#                                               rather than through JSON
#                       diff_file is a handoff buffer, not a generated artifact: it is left for
#                       the OS temp reaper, and no caller is expected to delete it.
#   --with-untracked  → in the working and paths modes, also diff untracked, non-ignored files
#                       against /dev/null. Both modes skip `.bf/`, which holds skill artifacts
#                       rather than the change under review.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || { printf '{"error":"not_a_git_repo"}\n'; exit 0; }
cd "$root" || exit 0
with_diff=0; with_untracked=0
while :; do
  case "${1:-}" in
    --with-diff) with_diff=1; shift ;;
    --with-untracked) with_untracked=1; shift ;;
    *) break ;;
  esac
done
target="${1:-}"
untracked_spec=()

# `git diff --no-index` exits 1 whenever the files differ, so its status is not an error signal.
# NUL-delimited listing keeps names with spaces or non-ASCII bytes intact; every `git diff` here
# sets core.quotePath=false so a non-ASCII name stays unquoted in the `diff --git` header. Names
# with `"`, `\` or control characters are still C-quoted there; hdr_name below unquotes them. A
# newline in a name still splits the line-based file lists.
untracked_diff() {
  [ "${#untracked_spec[@]}" -gt 0 ] || return 0
  local f
  while IFS= read -r -d '' f; do
    git -c core.quotePath=false diff --no-index "$@" -- /dev/null "$f" 2>/dev/null
  done < <(git ls-files -z --others --exclude-standard -- "${untracked_spec[@]}" 2>/dev/null)
  return 0
}

base_ref() {
  local head; head=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)
  git merge-base HEAD "$head" 2>/dev/null || git rev-parse HEAD~1 2>/dev/null
}

# diff_args and untracked_spec record the resolved target once per mode, so the optional
# `git diff -w` pass below reuses the same resolution instead of restating the mode logic.
if [ -z "$target" ]; then
  mode=working; diff_args=(HEAD); diff=$(git -c core.quotePath=false diff "${diff_args[@]}" 2>/dev/null)
  [ "$with_untracked" = 1 ] && untracked_spec=(. ':(exclude).bf')
elif [ "$target" = "branch" ]; then
  mode=branch; diff_args=("$(base_ref)"...HEAD); diff=$(git -c core.quotePath=false diff "${diff_args[@]}" 2>/dev/null)
elif git rev-parse --verify --quiet "$target" >/dev/null 2>&1 || [[ "$target" == *..* ]]; then
  mode=range; diff_args=("$target"); diff=$(git -c core.quotePath=false diff "${diff_args[@]}" 2>/dev/null)
else
  mode=paths; diff_args=(HEAD -- $target); diff=$(git -c core.quotePath=false diff "${diff_args[@]}" 2>/dev/null)
  [ "$with_untracked" = 1 ] && untracked_spec=($target ':(exclude).bf')
fi

if [ "${#untracked_spec[@]}" -gt 0 ]; then
  diff=$(printf '%s\n%s' "$diff" "$(untracked_diff)" | sed '/./,$!d')
fi
if [ "$mode" = working ] && [ -z "$diff" ]; then
  mode=branch; diff_args=("$(base_ref)"...HEAD); untracked_spec=()
  diff=$(git -c core.quotePath=false diff "${diff_args[@]}" 2>/dev/null)
fi

name_awk='
function hdr_name(line,   i, j, k, n, s, c, out) {
  if (line !~ /"$/) { sub(/^diff --git .* b\//, "", line); return line }
  for (i = length(line) - 3; i > 0; i--) if (substr(line, i, 4) == " \"b/") break
  s = substr(line, i + 4, length(line) - i - 4); out = ""
  for (j = 1; j <= length(s); j++) {
    c = substr(s, j, 1)
    if (c != "\\") { out = out c; continue }
    c = substr(s, ++j, 1)
    # git writes bytes 7..13 as \a \b \t \n \v \f \r, in that order
    if (c ~ /[abtnvfr]/) out = out sprintf("%c", index("abtnvfr", c) + 6)
    else if (c ~ /[0-7]/) { n = 0; for (k = 0; k < 3; k++) n = n * 8 + substr(s, j + k, 1); j += 2; out = out sprintf("%c", n) }
    else out = out c
  }
  return out
}
function json_str(s,   i, k, c, out) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\" || c == "\"") out = out "\\" c
    else if (c < " ") { for (k = 1; k < 32 && sprintf("%c", k) != c; k++); out = out sprintf("\\u%04x", k) }
    else out = out c
  }
  return out
}
'

files=$(printf '%s' "$diff" | awk "$name_awk"'/^diff --git / { print hdr_name($0) }')
n=$(printf '%s' "$files" | grep -c . || true)
added=$(printf '%s' "$diff" | grep -c '^+[^+]' || true)
removed=$(printf '%s' "$diff" | grep -c '^-[^-]' || true)

json_list() { printf '%s' "$1" | awk "$name_awk"'length { printf "%s\"%s\"", (n++ ? "," : ""), json_str($0) }'; }

extra=
if [ "$with_diff" = 1 ]; then
  diff_file=$(mktemp)
  printf '%s\n' "$diff" > "$diff_file"

  # Whitespace-only is decided per file, not per hunk: adjacent hunks merge under -w, so hunk
  # numbers do not correspond between the two diffs. A file with no hunk left under -w has no
  # non-whitespace change.
  # An errored -w pass must stay distinguishable from "every file is whitespace-only": both
  # produce no hunks, and the second branch below would then drop every file from the caller's
  # tour. Capture the status separately and, on a real failure, mark nothing whitespace-only.
  ws_diff=$(git -c core.quotePath=false diff -w "${diff_args[@]}" 2>/dev/null); ws_rc=$?
  ws_diff=$(printf '%s\n%s' "$ws_diff" "$(untracked_diff -w)")
  ws_hunked=$(printf '%s\n' "$ws_diff" | awk "$name_awk"'
    /^diff --git / { f = hdr_name($0); next }
    /^@@/ { if (f != "" && !seen[f]++) print f }')
  if [ "$ws_rc" != 0 ]; then
    whitespace_only=
  elif [ -n "$ws_hunked" ]; then
    whitespace_only=$(printf '%s\n' "$files" | grep . | grep -vxF "$ws_hunked" || true)
  else
    whitespace_only=$(printf '%s\n' "$files" | grep . || true)
  fi

  hunks=$(awk "$name_awk"'
    /^diff --git / { f = json_str(hdr_name($0)); idx=0; next }
    /^@@/ { n++; cur=n; hf[n]=f; hi[n]=++idx; hl[n]=NR; add[n]=0; rem[n]=0; next }
    cur && /^\+[^+]/ { add[cur]++ }
    cur && /^-[^-]/  { rem[cur]++ }
    END { for (i = 1; i <= n; i++)
            printf "%s{\"file\":\"%s\",\"index\":%d,\"line\":%d,\"added\":%d,\"removed\":%d}", \
              (i > 1 ? "," : ""), hf[i], hi[i], hl[i], add[i], rem[i] }' "$diff_file")

  extra=$(printf ',"diff_file":"%s","whitespace_only_files":[%s],"hunks":[%s]' \
    "$diff_file" "$(json_list "$whitespace_only")" "$hunks")
fi

printf '{"root":"%s","mode":"%s","file_count":%s,"added":%s,"removed":%s,"files":[%s]%s}\n' \
  "$root" "$mode" "${n:-0}" "${added:-0}" "${removed:-0}" "$(json_list "$files")" "$extra"
