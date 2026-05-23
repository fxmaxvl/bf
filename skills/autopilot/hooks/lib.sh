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
