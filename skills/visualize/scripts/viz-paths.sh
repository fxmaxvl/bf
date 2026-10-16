#!/usr/bin/env bash
# Classify a bf doc and resolve every path bf:visualize needs, in one call. Never writes or creates anything.
#
# Usage:  viz-paths.sh <doc-path>
# Output: single-line JSON
#         {kind, slug, doc, project_root, in_git, model_path, build_dir, html_path, mapping_path, model_exists}
#         kind is arch-audit or design; project_root is "" for a design doc outside git.
# Errors: {"error":...,"detail":...} + exit 1 — missing_arg, doc_not_found, unsupported_input,
#         nothing_to_visualize, no_project_root, jq_missing.
#
# The literals below are produced by other skills: the three H2 rows come from design/generate/SKILL.md
# and the -arch-audit.md suffix from arch-audit/scripts/run-state.sh; visualize-smoke.sh greps both.
set -euo pipefail

fail() { jq -cn --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'; exit 1; }
command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }

[ $# -ge 1 ] && [ -n "$1" ] || fail missing_arg "usage: viz-paths.sh <doc-path>"
[ -f "$1" ] || fail doc_not_found "no such file: $1"

doc_dir=$(cd "$(dirname "$1")" && pwd -P)
base=$(basename "$1")
doc=$doc_dir/$base

has_h2() { grep -qFx -- "## $1" "$doc"; }

kind=; slug=
case "$base" in
  *-arch-audit.md) kind=arch-audit; slug=${base%-arch-audit.md}-arch ;;
  *-design.md) kind=design; slug=${base%-design.md} ;;
  *) if printf '%s' "$base" | grep -Eq -- '-design-[0-9]+\.md$'; then
       stem=${base%.md}; n=${stem##*-}; kind=design; slug=${stem%-design-*}-$n
     fi ;;
esac
if [ -z "$kind" ] && has_h2 'Summary' && has_h2 'Actors & systems' && has_h2 'Proposed design'; then
  kind=design; slug=${base%.md}
fi
[ -n "$kind" ] || fail unsupported_input "expected an arch-audit doc (*-arch-audit.md) or a design doc (*-design.md, or one with ## Summary, ## Actors & systems and ## Proposed design)"

git_root=$(cd "$doc_dir" && git rev-parse --show-toplevel 2>/dev/null || true)
in_git=false; [ -z "$git_root" ] || in_git=true

if [ "$kind" = design ]; then
  actors_empty=$(awk '
    { sub(/[ \t\r]+$/, "") }
    $0 == "## Actors & systems" { seen = 1; next }
    seen && /^## / { exit }
    seen && $0 != "" { found = 1; exit }
    END { if (seen && !found) print "yes" }' "$doc")
  [ "$actors_empty" != yes ] || fail nothing_to_visualize "the ## Actors & systems section is empty — nothing to put on a context diagram"
  project_root=$git_root
  model_path=$doc_dir/$slug.c4
else
  case "$doc_dir" in
    */.bf/audits) project_root=$(dirname "$(dirname "$doc_dir")") ;;
    *) project_root=$git_root ;;
  esac
  [ -n "$project_root" ] || fail no_project_root "$base is outside .bf/audits/ and not in a git repo, so the audited repo root is unknown"
  model_path=$project_root/docs/architecture/$slug.c4
fi

build_dir=${project_root:-$HOME}/.bf/visualize/$slug
model_exists=false; [ ! -f "$model_path" ] || model_exists=true

jq -cn --arg kind "$kind" --arg slug "$slug" --arg doc "$doc" --arg root "$project_root" --argjson in_git "$in_git" \
  --arg model "$model_path" --arg build "$build_dir" --argjson me "$model_exists" \
  '{kind:$kind, slug:$slug, doc:$doc, project_root:$root, in_git:$in_git, model_path:$model,
    build_dir:$build, html_path:($build+"/index.html"), mapping_path:($build+"/mapping.md"), model_exists:$me}'
