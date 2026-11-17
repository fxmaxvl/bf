#!/usr/bin/env bash
# Parse bf:cross-agent arguments, create the bundle dir and write its manifest. Emits one JSON object.
#
# Usage: cross-agent-init.sh <<'BF_ARGS'
#          [--run <agent>] <skill> [skill arguments...]
#        BF_ARGS
#   bf:cross-agent flags come before the skill name. Everything after the skill name is the target skill's
#   arguments and is kept verbatim (spaces, quotes, #, newlines) in <bundle_dir>/args.txt.
#   <skill> is a bf skill directory name, with or without a leading "/bf:" or "bf:".
#
# Output keys: skill, run (agent name or null), project_root, plugin_root, bundle_dir, manifest,
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
re_skill="^(${nws}+)${ws}*"

run=""
[[ $text =~ $re_lead ]] && text=${text:${#BASH_REMATCH[0]}}
while [[ $text == --* ]]; do
  if [[ $text =~ $re_run ]]; then
    run=${BASH_REMATCH[2]}; text=${text:${#BASH_REMATCH[0]}}
  else
    die unknown_flag "only --run <agent> may come before the skill name"
  fi
done
[[ $text =~ $re_skill ]] || die missing_skill "name the bf skill to run"
skill=${BASH_REMATCH[1]}
args=${text:${#BASH_REMATCH[0]}}
# The heredoc that carries the arguments always ends them with a newline that is not part of them.
while [[ $args == *$'\n' ]]; do args=${args%$'\n'}; done
skill=${skill#/}; skill=${skill#bf:}

[ "$skill" = cross-agent ] && die self_target "bf:cross-agent cannot run itself"
[ -f "$plugin/skills/$skill/SKILL.md" ] || die unknown_skill "no skill '$skill' under $plugin/skills"

runners=$(cd "$runners_dir" && for f in *.sh; do [ -f "$f" ] && echo "${f%.sh}"; done)
if [ -n "$run" ] && ! grep -Fxq -- "$run" <<< "$runners"; then
  die unknown_runner "no runner '$run'; available: $(tr '\n' ' ' <<< "$runners")"
fi

conv=$(cd "$root" && bash "$plugin/skills/scan-conventions/scripts/resolve-conventions.sh" guidelines prose) \
  || die conventions_failed "resolve-conventions.sh failed"

# Breadth-first over ${CLAUDE_PLUGIN_ROOT} references. Only .md files are followed: scripts are run,
# not read, so their own references never reach the agent.
seen=$(mktemp); trap 'rm -f "$seen"' EXIT
queue=("conventions/plugin-main.md" "skills/$skill/SKILL.md")
for f in "$plugin/skills/$skill"/references/*.md; do [ -f "$f" ] && queue+=("${f#"$plugin"/}"); done
printf '%s\n' "${queue[@]}" > "$seen"
i=0
while [ $i -lt ${#queue[@]} ]; do
  f=${queue[$i]}; i=$((i + 1))
  while IFS= read -r ref; do
    ref=${ref#'${CLAUDE_PLUGIN_ROOT}/'}; ref=${ref%.}
    [ -f "$plugin/$ref" ] || continue
    grep -Fxq -- "$ref" "$seen" && continue
    echo "$ref" >> "$seen"
    case "$ref" in *.md) queue+=("$ref") ;; esac
  done < <(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$plugin/$f" 2>/dev/null | sort -u)
done

stamp=$(date +%Y%m%d-%H%M%S)
bundle="$root/.bf/cross-agent/$stamp-$skill"
n=2
while [ -e "$bundle" ]; do bundle="$root/.bf/cross-agent/$stamp-$skill-$n"; n=$((n + 1)); done
mkdir -p "$bundle" || die mkdir_failed "cannot create $bundle"
printf '%s' "$args" > "$bundle/args.txt"

jq -n \
  --arg skill "$skill" --arg run "$run" --arg root "$root" --arg plugin "$plugin" --arg bundle "$bundle" \
  --argjson conv "$conv" \
  --arg runners "$runners" --arg seen "$(cat "$seen")" '
  ($seen | split("\n") | map(select(. != ""))) as $refs
  | {skill: $skill,
     run: (if $run == "" then null else $run end),
     project_root: $root, plugin_root: $plugin, bundle_dir: $bundle,
     manifest: ($bundle + "/manifest.json"),
     runners: ($runners | split("\n") | map(select(. != ""))),
     docs: ([$refs[0]] | map($plugin + "/" + .))
           + ([$conv.guidelines, $conv.prose] | map(select(. != null)))
           + ($refs[1:] | map(select(endswith(".md"))) | map($plugin + "/" + .)),
     scripts: ($refs | map(select(endswith(".md") | not)) | map($plugin + "/" + .))}' \
  | tee "$bundle/manifest.json"
