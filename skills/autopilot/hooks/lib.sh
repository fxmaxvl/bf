#!/usr/bin/env bash
# Shared helpers for autopilot hooks. Source this file; do not execute directly.

# Derive a stable project identifier from the git remote URL, falling back to
# the repository basename. Mirrors the same logic in install.sh — if you change
# this derivation, update install.sh to match (and vice-versa).
_derive_project_id() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local pid
  pid=$(git config --get remote.origin.url 2>/dev/null \
    | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
  [ -z "$pid" ] && pid=$(basename "$repo_root")
  echo "$pid"
}
