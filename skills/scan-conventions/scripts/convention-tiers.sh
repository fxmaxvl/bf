#!/usr/bin/env bash
# Sourced, not executed: defines convention_tiers, the one ordered list of convention tiers.
# convention_tiers [PROJECT_ROOT] prints `<tier>\t<dir>` per line, highest priority first:
# project (only inside a git repo or when PROJECT_ROOT is given), user, plugin.

convention_tiers() {
  local project_root=${1:-} plugin_root
  [ -n "$project_root" ] || project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
  [ -z "$project_root" ] || printf 'project\t%s\n' "$project_root/.bf/conventions"
  printf 'user\t%s\n' "$HOME/.bf/conventions"
  printf 'plugin\t%s\n' "$plugin_root/conventions"
}
