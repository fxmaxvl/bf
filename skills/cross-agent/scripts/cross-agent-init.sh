#!/usr/bin/env bash
# Parse bf:cross-agent arguments, create the bundle dir and write its manifest. Emits one JSON object.
#
# Usage: cross-agent-init.sh < <args file>
#   The args file holds "[--run <agent>] [--read-only] <skill> [skill arguments...]", written by the Write tool.
#   bf:cross-agent flags come before the skill name. Everything after the skill name is the target skill's
#   arguments and is kept verbatim (spaces, quotes, #, newlines) in <bundle_dir>/args.txt.
#   <skill> is a bf skill directory name, with or without a leading "/bf:" or "bf:", or one sub-skill
#   under it as <skill>/<sub-skill> (feature/consistency-gate).
#   --read-only sets the manifest's sandbox to read-only. Without it the sandbox is workspace-write.
#
# Output keys: skill, run (agent name or null), sandbox, project_root, plugin_root, bundle_dir, manifest,
#   runners (available agent names), docs (absolute .md paths to read, in order), scripts (absolute
#   .sh paths the docs reference).
# manifest.json in the bundle holds the same object. args.txt holds the target skill's arguments.
# -h, --help prints this text on stdout and exits 0.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../../.." && pwd)
runners_dir="$here/../runners"

die() {
  if command -v jq >/dev/null; then jq -nc --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'
  else printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; fi
  exit 1
}
for arg in "$@"; do
  case "$arg" in -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
done
command -v jq >/dev/null || die no_jq "jq is required"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die not_a_git_repo "run inside a git repository"

text=$(cat; printf x); text=${text%x}
ws=$'[ \t\n]'
nws=$'[^ \t\n]'
re_lead="^${ws}+"
re_run="^--run(=|${ws}+)(${nws}+)${ws}*"
re_ro="^--read-only(${ws}+|$)"
# Only the separator after the skill name is consumed: spaces and tabs, then at most one newline,
# so an indented first argument line keeps its indent.
hws=$'[ \t]*'
nl=$'\n'
re_skill="^(${nws}+)${hws}(${nl})?"

run=""; sandbox=workspace-write
[[ $text =~ $re_lead ]] && text=${text:${#BASH_REMATCH[0]}}
while [[ $text == --* ]]; do
  if [[ $text =~ $re_run ]]; then
    run=${BASH_REMATCH[2]}; text=${text:${#BASH_REMATCH[0]}}
  elif [[ $text =~ $re_ro ]]; then
    sandbox=read-only; text=${text:${#BASH_REMATCH[0]}}
  else
    die unknown_flag "only --run <agent> and --read-only may come before the skill name"
  fi
done
[[ $text =~ $re_skill ]] || die missing_skill "name the bf skill to run"
skill=${BASH_REMATCH[1]}
args=${text:${#BASH_REMATCH[0]}}
# A file written as text usually ends in one newline that is not part of the arguments.
args=${args%$'\n'}
skill=${skill#/}; skill=${skill#bf:}
# The name becomes a path twice (the skill lookup and the bundle dir), so it must be one plain directory
# name or one sub-skill under it: "cross-agent/" or "../x" would get past the self check or escape skills/ and .bf/.
re_name='^[a-z0-9][a-z0-9-]*(/[a-z0-9][a-z0-9-]*)?$'
# The detail lists the skills, so SKILL.md can offer them without a shell command it is not allowed to run.
skill_list() {
  for d in "$plugin"/skills/*/SKILL.md; do d=${d%/SKILL.md}; d=${d##*/}; [ "$d" = cross-agent ] || printf '%s ' "$d"; done
}
[[ $skill =~ $re_name ]] || die unknown_skill "'$skill' is not a bf skill name. Skills: $(skill_list)"

[ "${skill%%/*}" = cross-agent ] && die self_target "bf:cross-agent cannot run itself"
[ -f "$plugin/skills/$skill/SKILL.md" ] || die unknown_skill "no skill '$skill'. Skills: $(skill_list)"

runners=$(cd "$runners_dir" && for f in *.sh; do [ -f "$f" ] && echo "${f%.sh}"; done)
if [ -n "$run" ] && ! grep -Fxq -- "$run" <<< "$runners"; then
  die unknown_runner "no runner '$run'; available: $(tr '\n' ' ' <<< "$runners")"
fi

conv=$(cd "$root" && bash "$plugin/skills/scan-conventions/scripts/resolve-conventions.sh" guidelines prose) \
  || die conventions_failed "resolve-conventions.sh failed"

# Breadth-first over the plugin files each doc cites. Skills cite them as ${CLAUDE_PLUGIN_ROOT}/<path>,
# as a bare skills/<path> ("<resolved absolute path to skills/...>"), relative to skills/ in sub-skill
# tables, or relative to their own directory (references/fix.md). Only .md files are followed: scripts
# are run, not read, so their own citations never reach the agent.
seen=$(mktemp); trap 'rm -f "$seen"' EXIT
queue=("conventions/plugin-main.md" "skills/$skill/SKILL.md")
for f in "$plugin/skills/$skill"/references/*.md; do [ -f "$f" ] && queue+=("${f#"$plugin"/}"); done
printf '%s\n' "${queue[@]}" > "$seen"
i=0
while [ $i -lt ${#queue[@]} ]; do
  f=${queue[$i]}; i=$((i + 1))
  while IFS= read -r ref; do
    ref=${ref#'${CLAUDE_PLUGIN_ROOT}/'}; ref=${ref#/}
    case "$ref" in */*) ;; *) continue ;; esac
    case "/$ref/" in */../*) continue ;; esac
    hit=""
    for cand in "$ref" "skills/$ref" "${f%/*}/$ref"; do
      [ -f "$plugin/$cand" ] && { hit=$cand; break; }
    done
    [ -n "$hit" ] || continue
    grep -Fxq -- "$hit" "$seen" && continue
    echo "$hit" >> "$seen"
    case "$hit" in *.md) queue+=("$hit") ;; esac
  done < <(grep -oE '(\$\{CLAUDE_PLUGIN_ROOT\}/)?[A-Za-z0-9_./-]+\.(md|sh)' "$plugin/$f" 2>/dev/null | sort -u)
done

stamp=$(date +%Y%m%d-%H%M%S)
parent="$root/.bf/cross-agent"
mkdir -p "$parent" || die mkdir_failed "cannot create $parent"
# A plain mkdir is the claim: it fails when the dir exists, so two inits in the same second never share one.
bundle="$parent/$stamp-${skill//\//-}"; n=2
until mkdir "$bundle" 2>/dev/null; do
  [ -e "$bundle" ] || die mkdir_failed "cannot create $bundle"
  bundle="$parent/$stamp-${skill//\//-}-$n"; n=$((n + 1))
done
printf '%s' "$args" > "$bundle/args.txt"

# Built in memory first: a failed jq must not leave an empty manifest.json that a later step trusts.
# A sum as an object value needs its own parentheses: jq 1.6 rejects `{docs: a + b}`.
manifest=$(jq -n \
  --arg skill "$skill" --arg run "$run" --arg sandbox "$sandbox" --arg root "$root" --arg plugin "$plugin" --arg bundle "$bundle" \
  --argjson conv "$conv" \
  --arg runners "$runners" --arg seen "$(cat "$seen")" '
  ($seen | split("\n") | map(select(. != ""))) as $refs
  | {skill: $skill,
     run: (if $run == "" then null else $run end),
     sandbox: $sandbox,
     project_root: $root, plugin_root: $plugin, bundle_dir: $bundle,
     manifest: ($bundle + "/manifest.json"),
     runners: ($runners | split("\n") | map(select(. != ""))),
     docs: (([$refs[0]] | map($plugin + "/" + .))
            + ([$conv.guidelines, $conv.prose] | map(select(. != null)))
            + ($refs[1:] | map(select(endswith(".md"))) | map($plugin + "/" + .))),
     scripts: ($refs | map(select(endswith(".md") | not)) | map($plugin + "/" + .))}') \
  || { rm -rf "$bundle"; die manifest_failed "could not build the manifest for $skill"; }
printf '%s\n' "$manifest" > "$bundle/manifest.json" || { rm -rf "$bundle"; die mkdir_failed "cannot write $bundle/manifest.json"; }
printf '%s\n' "$manifest"
