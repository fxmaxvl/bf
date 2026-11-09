#!/usr/bin/env bash
# session-untracked.sh: List the untracked files outside .bf/ that a session may treat as its own.
# Prints repo-relative paths, NUL-delimited, from the repo root.
# Usage: bash session-untracked.sh [--baseline <file>]
#   --baseline  NUL-delimited list of files that were untracked at session start
#               (state-ops.sh paths.untracked_baseline). Entries in it are left out. An entry that
#               ends in "/" covers everything under it. Without it, every untracked file is listed.
# An untracked directory that holds its own .git (a nested clone or a worktree) is never listed,
# because staging it would record a gitlink. A note for each goes to stderr.

set -euo pipefail

BASELINE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline) BASELINE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

AT_START=()
if [[ -n "$BASELINE" ]]; then
    [[ -f "$BASELINE" ]] || { echo "Error: baseline $BASELINE not found" >&2; exit 1; }
    while IFS= read -r -d '' F; do AT_START+=("$F"); done < "$BASELINE"
fi

in_baseline() {
    local f="$1" a
    for a in ${AT_START[@]+"${AT_START[@]}"}; do
        [[ "$f" == "$a" || "$f" == "${a%/}/"* ]] && return 0
    done
    return 1
}

cd "$(git rev-parse --show-toplevel)"
while IFS= read -r -d '' F; do
    if [[ "$F" == */ ]]; then
        echo "Note: skipping $F: it is a nested git repo." >&2
        continue
    fi
    in_baseline "$F" || printf '%s\0' "$F"
done < <(git ls-files -z --others --exclude-standard -- . ':!.bf')
