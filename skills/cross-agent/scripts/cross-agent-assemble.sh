#!/usr/bin/env bash
# Build <bundle_dir>/prompt.md from the manifest, the preamble, brief.md and args.txt. Emits one JSON object.
#
# Usage: cross-agent-assemble.sh <bundle_dir>
#   The bundle must hold manifest.json and args.txt (from cross-agent-init.sh) and a non-empty brief.md.
#   prompt.md is written only when every input is present and the manifest has every key.
#
# Output keys: prompt (absolute path), bytes, run_commands ({agent: command} for every runner).
# -h, --help prints this text on stdout and exits 0.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1. Codes: no_jq, usage, no_manifest, bad_manifest,
#   no_args, no_brief, write_failed.
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
# Every later jq read trusts these keys, so a partial manifest is refused here, not halfway through the prompt.
jq -e '(.skill, .plugin_root, .project_root, .bundle_dir | type == "string")
       and (.docs, .scripts, .runners | type == "array")' "$manifest" >/dev/null 2>&1 \
  || die bad_manifest "$manifest is not a manifest written by cross-agent-init.sh"
[ -f "$bundle/args.txt" ] || die no_args "$bundle/args.txt is missing. Run cross-agent-init.sh first"
[ -s "$bundle/brief.md" ] || die no_brief "$bundle/brief.md is missing or empty"

skill=$(jq -r .skill "$manifest")
args=$(cat "$bundle/args.txt"; printf x); args=${args%x}
# The arguments are fenced by a marker they cannot contain, so the agent sees where they end.
fence=ARGS; n=2
while grep -Fq -- "$fence" <<< "$args"; do fence="ARGS_$n"; n=$((n + 1)); done

# Written aside and moved into place, so a failed write never leaves a prompt.md that a runner would accept.
tmp_prompt="$bundle/prompt.md.tmp"
{
  printf '# Cross-agent run: bf:%s\n\n' "$skill"
  cat "$preamble"
  printf '\n## Paths\n\n'
  jq -r '"- Plugin root, the value of `${CLAUDE_PLUGIN_ROOT}`: `\(.plugin_root)`",
         "- Project root, your working directory: `\(.project_root)`",
         "- Bundle dir: `\(.bundle_dir)`"' "$manifest"
  # The closure can reach dozens of sub-skill docs. Only the conventions and the skill's own files are
  # read up front, the rest when the skill points at them.
  printf '\n## Read first, in this order\n\n'
  jq -r '(.plugin_root + "/skills/" + .skill + "/") as $own
         | [.docs[] | select(. == $own + "SKILL.md" or startswith($own + "references/") or (contains("/skills/") | not))]
         | to_entries[] | "\(.key + 1). `\(.value)`"' "$manifest"
  printf '\n## Docs the skill cites, read each when the skill sends you to it\n\n'
  jq -r '(.plugin_root + "/skills/" + .skill + "/") as $own
         | [.docs[] | select(contains("/skills/") and . != $own + "SKILL.md" and (startswith($own + "references/") | not))]
         | if length == 0 then "None." else .[] | "- `\(.)`" end' "$manifest"
  printf '\n## Scripts the skill calls\n\n'
  jq -r 'if (.scripts | length) == 0 then "None." else .scripts[] | "- `\(.)`" end' "$manifest"
  printf '\n## Task brief\n\n'
  cat "$bundle/brief.md"
  printf '\n\n## Arguments\n\n'
  printf 'The skill'"'"'s `$ARGUMENTS` is the text between the two `%s` lines, verbatim. It may be empty.\n\n' "$fence"
  printf '%s\n%s\n%s\n' "$fence" "$args" "$fence"
  printf '\n## Start\n\nRead the files under **Read first** in order. Then run bf:%s from its SKILL.md with the arguments above, under the rules at the top of this prompt.\n' "$skill"
} > "$tmp_prompt" && mv "$tmp_prompt" "$bundle/prompt.md" \
  || { rm -f "$tmp_prompt"; die write_failed "cannot write $bundle/prompt.md"; }

jq -n --arg p "$bundle/prompt.md" --argjson b "$(wc -c < "$bundle/prompt.md" | tr -d ' ')" \
  --arg dir "$runners_dir" --arg bundle "$bundle" --arg root "$(jq -r .project_root "$manifest")" \
  --argjson agents "$(jq .runners "$manifest")" '
  {prompt: $p, bytes: $b,
   run_commands: ($agents | map({key: ., value: ("bash " + ([$dir + "/" + . + ".sh", $bundle, $root] | map(@sh) | join(" ")))}) | from_entries)}'
