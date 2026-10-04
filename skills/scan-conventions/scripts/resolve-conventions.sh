#!/usr/bin/env bash
# Resolve named conventions through the 3-step lookup in plugin-main.md, first match wins:
# <project_root>/.bf/conventions, then ~/.bf/conventions, then the plugin's conventions/.
#
# Usage: resolve-conventions.sh <name> [<name>...]     e.g. resolve-conventions.sh dev testing git
# Output: one JSON object mapping each name to the winning absolute path, or null when no tier
#         has it — {"dev":"/abs/dev.md","testing":null}
# Errors: {"error":"usage"} + exit 2 when no name is given.
set -uo pipefail

[ $# -gt 0 ] || { printf '{"error":"usage","detail":"resolve-conventions.sh <name>..."}\n'; exit 2; }

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

out=
for name in "$@"; do
  name=${name%.md}
  path=null
  for dir in ${project_root:+"$project_root/.bf/conventions"} "$HOME/.bf/conventions" "$plugin_root/conventions"; do
    if [ -f "$dir/$name.md" ]; then path=$(json_str "$dir/$name.md"); break; fi
  done
  out="$out${out:+,}$(json_str "$name"):$path"
done
printf '{%s}\n' "$out"
