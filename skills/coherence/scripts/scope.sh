#!/usr/bin/env bash
# Resolve the scope of a change to assess. Emits one JSON object.
#
# Usage: scope.sh [--with-diff] [target]
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
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || { printf '{"error":"not_a_git_repo"}\n'; exit 0; }
cd "$root" || exit 0
with_diff=0
if [ "${1:-}" = "--with-diff" ]; then with_diff=1; shift; fi
target="${1:-}"

base_ref() {
  local head; head=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)
  git merge-base HEAD "$head" 2>/dev/null || git rev-parse HEAD~1 2>/dev/null
}

# diff_args records the resolved target once per mode, so the optional `git diff -w` pass below
# reuses the same resolution instead of restating the mode logic.
if [ -z "$target" ]; then
  mode=working; diff_args=(HEAD); diff=$(git diff "${diff_args[@]}" 2>/dev/null)
  if [ -z "$diff" ]; then
    mode=branch; diff_args=("$(base_ref)"...HEAD); diff=$(git diff "${diff_args[@]}" 2>/dev/null)
  fi
elif [ "$target" = "branch" ]; then
  mode=branch; diff_args=("$(base_ref)"...HEAD); diff=$(git diff "${diff_args[@]}" 2>/dev/null)
elif git rev-parse --verify --quiet "$target" >/dev/null 2>&1 || [[ "$target" == *..* ]]; then
  mode=range; diff_args=("$target"); diff=$(git diff "${diff_args[@]}" 2>/dev/null)
else
  mode=paths; diff_args=(HEAD -- $target); diff=$(git diff "${diff_args[@]}" 2>/dev/null)
fi

files=$(printf '%s' "$diff" | sed -n 's#^diff --git a/.* b/##p')
n=$(printf '%s' "$files" | grep -c . || true)
added=$(printf '%s' "$diff" | grep -c '^+[^+]' || true)
removed=$(printf '%s' "$diff" | grep -c '^-[^-]' || true)

json_list() { printf '%s' "$1" | grep . | sed 's/"/\\"/g; s/^/"/; s/$/"/' | paste -sd, -; }

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
  ws_diff=$(git diff -w "${diff_args[@]}" 2>/dev/null); ws_rc=$?
  ws_hunked=$(printf '%s\n' "$ws_diff" | awk '
    /^diff --git a\// { f=$0; sub(/^diff --git a\/.* b\//, "", f); next }
    /^@@/ { if (f != "" && !seen[f]++) print f }')
  if [ "$ws_rc" != 0 ]; then
    whitespace_only=
  elif [ -n "$ws_hunked" ]; then
    whitespace_only=$(printf '%s\n' "$files" | grep . | grep -vxF "$ws_hunked" || true)
  else
    whitespace_only=$(printf '%s\n' "$files" | grep . || true)
  fi

  hunks=$(awk '
    /^diff --git a\// { f=$0; sub(/^diff --git a\/.* b\//, "", f); gsub(/"/, "\\\"", f); idx=0; next }
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
