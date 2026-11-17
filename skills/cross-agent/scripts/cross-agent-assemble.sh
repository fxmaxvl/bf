#!/usr/bin/env bash
# Build <bundle_dir>/prompt.md from the manifest, the preamble, brief.md and args.txt. Emits one JSON object.
#
# Usage: cross-agent-assemble.sh <bundle_dir>
#   The bundle must hold manifest.json and args.txt (from cross-agent-init.sh) and a non-empty brief.md.
#
# Output keys: prompt (absolute path), bytes, run_commands ({agent: command} for every runner).
# -h, --help prints this text on stdout and exits 0.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
preamble="$here/../references/preamble.md"
runners_dir=$(cd "$here/../runners" && pwd)

die() { jq -nc --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'; exit 1; }
case "${1-}" in -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
command -v jq >/dev/null || { echo '{"error":"no_jq","detail":"jq is required"}'; exit 1; }
[ $# -eq 1 ] || die usage "cross-agent-assemble.sh <bundle_dir>"
bundle=$1
manifest="$bundle/manifest.json"
[ -f "$manifest" ] || die no_manifest "$manifest is missing. Run cross-agent-init.sh first"
[ -s "$bundle/brief.md" ] || die no_brief "$bundle/brief.md is missing or empty"

skill=$(jq -r .skill "$manifest")
args=$(cat "$bundle/args.txt"; printf x); args=${args%x}
# The arguments are fenced by a marker they cannot contain, so the agent sees where they end.
fence=ARGS; n=2
while grep -Fq -- "$fence" <<< "$args"; do fence="ARGS_$n"; n=$((n + 1)); done

{
  printf '# Cross-agent run: bf:%s\n\n' "$skill"
  cat "$preamble"
  printf '\n## Paths\n\n'
  jq -r '"- Plugin root, the value of `${CLAUDE_PLUGIN_ROOT}`: `\(.plugin_root)`",
         "- Project root, your working directory: `\(.project_root)`",
         "- Bundle dir: `\(.bundle_dir)`"' "$manifest"
  printf '\n## Read first, in this order\n\n'
  jq -r '.docs | to_entries[] | "\(.key + 1). `\(.value)`"' "$manifest"
  printf '\n## Scripts the skill calls\n\n'
  jq -r 'if (.scripts | length) == 0 then "None." else .scripts[] | "- `\(.)`" end' "$manifest"
  printf '\n## Task brief\n\n'
  cat "$bundle/brief.md"
  printf '\n\n## Arguments\n\n'
  printf 'The skill'"'"'s `$ARGUMENTS` is the text between the two `%s` lines, verbatim. It may be empty.\n\n' "$fence"
  printf '%s\n%s\n%s\n' "$fence" "$args" "$fence"
  printf '\n## Start\n\nRead the files under **Read first** in order. Then run bf:%s from its SKILL.md with the arguments above, under the rules at the top of this prompt.\n' "$skill"
} > "$bundle/prompt.md"

jq -n --arg p "$bundle/prompt.md" --argjson b "$(wc -c < "$bundle/prompt.md" | tr -d ' ')" \
  --arg dir "$runners_dir" --arg bundle "$bundle" --arg root "$(jq -r .project_root "$manifest")" \
  --argjson agents "$(jq .runners "$manifest")" '
  {prompt: $p, bytes: $b,
   run_commands: ($agents | map({key: ., value: "bash \"\($dir)/\(.).sh\" \"\($bundle)\" \"\($root)\""}) | from_entries)}'
