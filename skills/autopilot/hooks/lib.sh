#!/usr/bin/env bash
# Shared helpers for autopilot hooks. Source this file; do not execute directly.

# Derive a stable project identifier from the git remote URL, falling back to
# the repository basename. This is the single source of truth — install.sh and
# stop.sh both source this file instead of duplicating the derivation.
_derive_project_id() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local pid
  pid=$(git config --get remote.origin.url 2>/dev/null \
    | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
  [ -z "$pid" ] && pid=$(basename "$repo_root")
  echo "$pid"
}

# A stop prompt has at most three words and starts with a stop word. So "hold on" and
# "no, don't push" stop the run, and "don't stop the tests" or a status check like "so?" do not.
# There is no resume, so "pause" is not a stop word.
_is_stop_prompt() {
  local words
  words=$(printf '%s' "$1" | sed "s/[’']//g" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' ')
  # shellcheck disable=SC2086
  set -- $words
  [ "$#" -ge 1 ] && [ "$#" -le 3 ] || return 1
  case $1 in stop|cancel|abort|halt|kill|wait|hold|no|off) return 0 ;; esac
  return 1
}
