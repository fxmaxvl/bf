#!/usr/bin/env bash
# Shared directory guard for the hooks. Source this file. Do not execute it. It sets no shell options and no
# trap, so a caller keeps its own.

# dir_guard_check <dir> <uid> [private]: succeeds when dir is a real directory (not a symlink) that belongs
# to uid. With "private" the directory must also give no access to group or other. Ls prints the mode in
# field 1 and the owner uid in field 3 on both BSD and GNU, where stat flags differ.
dir_guard_check() {
  local dir=$1 uid=$2 mode owner
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  read -r mode _ owner _ < <(ls -nd "$dir")
  [ "$owner" = "$uid" ] || return 1
  [ "${3:-}" != private ] || [ "${mode:4:6}" = "------" ]
}
