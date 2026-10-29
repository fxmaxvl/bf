#!/usr/bin/env bash
# Deterministic groundwork for onboard-project: workspace paths, prior-course detection, and the
# repo signals that decide which curriculum areas exist — one call instead of dozens of globs.
# Usage:
#   onboard-probe.sh init [slug]        # slug defaults to "<repo>-onboarding"; always slugified
#   onboard-probe.sh verify <workspace> # lists lesson/reference links whose target file is missing;
#                                       # links quoted inside <pre>/<code> are sample text, not links
#   onboard-probe.sh promote <staging> <workspace>
#                                       # copies staged lessons/ and reference/ pages into the workspace;
#                                       # never overwrites, so an existing page is a conflict, not copied
#   onboard-probe.sh brief [path|-]     # capped repo signals for the one-page brief; no [path] = whole repo from any cwd; `-` reads it from stdin;
#                                       # an explicit [path] (including . and ..) resolves from the cwd and scopes to a subtree
# Output: single-line JSON.
#
# brief output contract:
#   repo, sha ("none" before the first commit), tracked_files (exact, within [path])
#   Path base: every path in the payload is repo-root-relative (units.*.path, signals.*.sample, units.by_top_dir keys,
#                units.groups[].dir, hot_dirs), except output_path (absolute); "(top-level)" is a sentinel, not a path.
#   path         [path] normalised to repo-root-relative with no trailing "/"; "" for the whole repo
#   output_name  <repo>.md, or <repo>--<path-slug>.md for a scoped run
#   output_path  absolute path of the page under <repo root>/.bf/onboard-brief/
#   units        {mode build|dir, count (exact), sample (first 30, shallowest first; dir mode is alphabetical),
#                 shown (first 8, the ones the page lists), by_top_dir ({first directory below [path], root-relative: units}; units directly
#                 below [path] go under "(top-level)"), groups ([{dir, remaining, examples}]: units under dir not in shown; examples are
#                 up to 3 names from sample[8:30]; remaining 0 is omitted)}
#   layout       empty (no tracked files) | flat (files, no units) | single (one unit) | dir (units are plain directories) | build
#   needs_agent  true when mode is build with more than 30 units, or tracked_files exceeds 2000,
#                and there is at least one group for the agent to annotate
#   hot_dirs     top 5 directories (up to two segments deep below [path], root-relative) by files touched in the last 200 commits, i.e. file paths
#                listed per commit, summed; root-level files and directories no longer in the tree are ignored; [] with no commits
#   signals      docs, manifests, data, apis, ci, infra, config, tests — each {count (exact), sample (first 15, shallowest first)};
#                all but ci are within [path]; ci is root-anchored, so a scoped run computes it from the whole repo
#   errors       not_a_git_repo, jq_not_found, not_a_directory, path_outside_repo (exit 1)
set -euo pipefail

command -v jq >/dev/null || { echo '{"error":"jq_not_found"}'; exit 1; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
teach_root="$HOME/.bf/teach"

slugify() { tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//'; }
json_lines() { { grep . || true; } | jq -R . | jq -sc .; }

# Strips a repo-relative directory prefix; "" when the string is the prefix itself.
STRIP='def strip($p): if . == $p then "" elif $p == "" then . elif startswith($p + "/") then .[($p | length) + 1:] else . end;'

# The probe owns these limits; the skill never restates them. Lists are capped so a monorepo with 4k protos
# doesn't flood the context; counts stay exact.
sample_cap=30 shown_cap=8 agent_units=30 agent_files=2000 signal_cap=15

# $2=rank puts shallow paths first (line order breaks ties) so root manifests and docs lead the sample.
signal() {
  { grep -E "$1" || true; } \
    | if [ "${2:-}" = rank ]; then awk '{print gsub(/\//,"/")"\t"NR"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f3-; else cat; fi \
    | json_lines | jq -c --argjson cap "$signal_cap" '{count:length, sample:.[0:$cap]}'
}

RX_DOCS='(^|/)(README|CONTRIBUTING|ARCHITECTURE|CLAUDE|AGENTS)[^/]*$|(^|/)(docs?|adrs?|decisions)/'
RX_MANIFESTS='(^|/)(package\.json|pom\.xml|build\.gradle(\.kts)?|BUILD(\.bazel)?|MODULE\.bazel|WORKSPACE|go\.mod|Cargo\.toml|pyproject\.toml|requirements[^/]*\.txt|Gemfile|composer\.json|[^/]*\.csproj|Makefile|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml)$'
RX_DATA='(^|/)(migrations?|db|schema|liquibase|flyway)/|\.sql$|schema\.prisma$|(^|/)[^/]*(entity|repository|dao)[^/]*\.[a-z]+$'
RX_APIS='\.proto$|(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$|\.graphqls?$|\.avsc$'
RX_CI='^\.github/workflows/|^\.gitlab-ci\.yml$|(^|/)Jenkinsfile$|^\.circleci/|^\.buildkite/|^azure-pipelines\.yml$'
RX_INFRA='\.tf$|(^|/)Chart\.yaml$|(^|/)(k8s|kubernetes|helm|deploy|infra)/'
RX_CONFIG='(^|/)\.env[^/]*$|(^|/)(config|conf|settings)[^/]*\.(ya?ml|json|toml|properties|conf)$|application[^/]*\.(ya?ml|properties)$'
RX_TESTS='(^|/)(tests?|__tests__|spec|it|e2e)/|[._-](test|spec)\.[a-z]+$|Test\.(java|scala|kt)$'

SIGNALS=("docs|$RX_DOCS" "manifests|$RX_MANIFESTS" "data|$RX_DATA" "apis|$RX_APIS" "ci|$RX_CI" "infra|$RX_INFRA" "config|$RX_CONFIG" "tests|$RX_TESTS")

# Builds {docs,…,tests} from $files; $ci_files (default $files) feeds ci. $1=rank passes through to signal().
signals_json() {
  local out='{}' e k src
  for e in "${SIGNALS[@]}"; do
    k=${e%%|*}; src=$files
    [ "$k" = ci ] && src=${ci_files:-$files}
    out=$(jq -c --arg k "$k" --argjson v "$(signal "${e#*|}" "${1:-}" <<<"$src")" '.[$k]=$v' <<<"$out")
  done
  printf '%s\n' "$out"
}

# Sets root, repo, base (slug of repo, "repo" fallback) and sha ("none" before the first commit); exits on a non-repo.
repo_identity() {
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo '{"error":"not_a_git_repo"}'; exit 1; }
  repo=$(basename "$root")
  base=$(printf '%s' "$repo" | slugify)
  [ -n "$base" ] || base=repo
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo none)
}

case "${1:-init}" in
  init)
    repo_identity
    cd "$root"
    slug=$(printf '%s' "${2:-$base-onboarding}" | slugify)
    [ -n "$slug" ] || { echo '{"error":"empty_slug"}'; exit 1; }
    workspace="$teach_root/$slug"
    files=$(git ls-files)

    # A free dated slug, so the skill never needs suffix logic of its own.
    fresh="$slug-$(date +%F)"
    n=2
    while [ -e "$teach_root/$fresh" ]; do fresh="$slug-$(date +%F)-$n"; n=$((n+1)); done

    profile=absent
    if [ -f "$teach_root/LEARNING-PROFILE.md" ]; then
      profile=$(sed -n 's/^Status:[[:space:]]*\([a-z]*\).*/\1/p' "$teach_root/LEARNING-PROFILE.md" | head -1)
      [ -n "$profile" ] || profile=unknown
    fi

    similar=$( (ls -1 "$teach_root" 2>/dev/null || true) | LC_ALL=C sort \
      | SLUG="$slug" BASE="$base" REPO="$repo" awk '
          BEGIN { s=ENVIRON["SLUG"]; b=tolower(ENVIRON["BASE"]); r=tolower(ENVIRON["REPO"]) }
          { n=tolower($0) }
          $0 == s { next }
          n == b || index(n, b "-") == 1 || n == r || index(n, r "-") == 1 { print }' \
      | json_lines)

    jq -nc \
      --arg root "$root" --arg repo "$repo" --arg slug "$slug" --arg ws "$workspace" \
      --arg fresh "$fresh" --arg facts "$root/.bf/onboard/$slug" --arg profile "$profile" \
      --arg sha "$sha" \
      --argjson exists "$([ -d "$workspace" ] && echo true || echo false)" \
      --argjson similar "$similar" \
      --argjson tracked "$(printf '%s\n' "$files" | grep -c . || true)" \
      --argjson units "$(bash "$here/../../arch-audit/scripts/detect-units.sh" .)" \
      --argjson signals "$(signals_json)" \
      '{root:$root, repo:$repo, sha:$sha, slug:$slug, workspace:$ws, workspace_exists:$exists,
        fresh_slug:$fresh, similar_workspaces:$similar, facts_dir:$facts, profile_status:$profile, tracked_files:$tracked,
        units:$units, signals:$signals}'
    ;;
  brief)
    # An omitted [path] is the whole repo; an explicit one resolves against the caller's cwd, before the cd below.
    repo_identity
    # `-` reads [path] from stdin, so a skill can pass free-form text through a quoted heredoc.
    want=${2:-}
    if [ "$want" = - ]; then
      want=$(cat)
      want="${want#"${want%%[![:space:]]*}"}"; want="${want%"${want##*[![:space:]]}"}"
    fi
    want=${want:-$root}
    [ -d "$want" ] || { echo '{"error":"not_a_directory"}'; exit 1; }
    abs=$(cd "$want" && pwd -P)
    rootp=$(cd "$root" && pwd -P)
    rel=$(jq -nr --arg p "$abs" --arg r "$rootp" "$STRIP"' $p | strip($r)') || exit 1
    case "$abs/" in "$rootp"/*) ;; *) echo '{"error":"path_outside_repo"}'; exit 1;; esac
    cd "$root"
    name=$base
    [ -z "$rel" ] || name="$base--$(printf '%s' "$rel" | slugify)"
    files=$(git ls-files -- "${rel:-.}")
    ci_files=$files
    [ -z "$rel" ] || ci_files=$(git ls-files)
    tracked=$(printf '%s\n' "$files" | grep -c . || true)

    units=$(bash "$here/../../arch-audit/scripts/detect-units.sh" "${rel:-.}" | jq -c \
      --arg rel "$rel" --argjson tracked "$tracked" --argjson cap "$sample_cap" --argjson shown "$shown_cap" \
      --argjson agent_units "$agent_units" --argjson agent_files "$agent_files" "$STRIP"'
      ($rel | if . == "" then "" else . + "/" end) as $pre |
      [.units[] | . + {dir: ((.path | strip($rel)) | if contains("/") then $pre + split("/")[0] else "(top-level)" end)}] as $u
      | ($u | length) as $n
      | ($u | group_by(.dir) | map({key: .[0].dir, value: length}) | from_entries) as $by
      | $u[0:$shown] as $sh
      | $u[$shown:$cap] as $tail
      | {mode, count: $n, sample: ($u[0:$cap] | map({name, path, marker})), shown: ($sh | map({name, path, marker})), by_top_dir: $by,
         groups: ([$by | keys[] as $d
                   | {dir: $d, remaining: ($by[$d] - ($sh | map(select(.dir == $d)) | length)),
                      examples: ([$tail[] | select(.dir == $d) | .name] | .[0:3])}
                   | select(.remaining > 0)] | sort_by(-.remaining, .dir))}
      | . + {layout: (if $tracked == 0 then "empty" elif $n == 0 then "flat" elif $n == 1 then "single" elif .mode == "dir" then "dir" else "build" end),
             needs_agent: (((.mode == "build" and $n > $agent_units) or $tracked > $agent_files) and (.groups | length) > 0)}')

    hot='[]'
    if git rev-parse -q --verify HEAD >/dev/null; then
      hot=$(git -c core.quotePath=false log -n 200 --name-only --format= -- "${rel:-.}" | { grep . || true; } \
        | jq -R "$STRIP"'strip($rel) | split("/")[:-1] | select(length > 0) | .[0:2] | join("/") | (if $rel == "" then "" else $rel + "/" end) + .' --arg rel "$rel" \
        | jq -sr 'group_by(.) | map({d: .[0], n: length}) | sort_by(-.n, .d) | .[].d' \
        | { k=0; while IFS= read -r d; do
              if [ "$k" -lt 5 ] && [ -d "$d" ]; then printf '%s\n' "$d"; k=$((k+1)); fi
            done; } | json_lines)
      # History names renamed and deleted directories too; only ones still in the tree are worth pointing at.
      # The loop counts to 5 itself: a head(1) here would close the pipe early and SIGPIPE under pipefail.
    fi

    jq -nc \
      --arg repo "$repo" --arg rel "$rel" --arg name "$name.md" \
      --arg out "$rootp/.bf/onboard-brief/$name.md" \
      --arg sha "$sha" \
      --argjson tracked "$tracked" --argjson units "$units" --argjson hot "$hot" \
      --argjson signals "$(signals_json rank)" \
      '{repo:$repo, sha:$sha, path:$rel, output_name:$name, output_path:$out, tracked_files:$tracked,
        layout:$units.layout, needs_agent:$units.needs_agent, units:($units | del(.layout, .needs_agent)), hot_dirs:$hot,
        signals:$signals}'
    ;;
  verify)
    ws=${2:?usage: onboard-probe.sh verify <workspace>}
    [ -d "$ws/lessons" ] || { jq -nc --arg ws "$ws" '{error:"no_lessons_dir", workspace:$ws}'; exit 1; }
    broken=()
    for page in "$ws"/lessons/*.html "$ws"/reference/*.html; do
      [ -f "$page" ] || continue
      dir=$(dirname "$page")
      while IFS= read -r href; do
        target=${href%%#*}
        target=${target%%\?*}
        [ -z "$target" ] && continue
        [ -f "$dir/$target" ] || broken+=("${page#"$ws"/} -> $href")
      done <<< "$(perl -0777 -pe 's{<(pre|code)\b[^>]*>.*?</\1>}{}gis' "$page" | grep -oE "(href|src)=(\"[^\"]+\"|'[^']+')" | sed -E "s/^(href|src)=[\"']//;s/[\"']\$//" | grep -vE '^(https?:|mailto:|#|file:|data:|//)' || true)"
    done
    jq -nc \
      --argjson lessons "$(find "$ws/lessons" -name '*.html' ! -name '0000-*' | wc -l | tr -d ' ')" \
      --argjson references "$( (find "$ws/reference" -name '*.html' 2>/dev/null || true) | wc -l | tr -d ' ')" \
      --argjson broken "$(printf '%s\n' "${broken[@]:-}" | json_lines)" \
      '{lessons:$lessons, references:$references, broken_links:$broken}'
    ;;
  promote)
    staging=${2:?usage: onboard-probe.sh promote <staging> <workspace>}
    ws=${3:?usage: onboard-probe.sh promote <staging> <workspace>}
    [ -d "$staging" ] || { jq -nc --arg s "$staging" '{error:"no_staging_dir", staging:$s}'; exit 1; }
    copied=(); conflicts=()
    for sub in lessons reference; do
      [ -d "$staging/$sub" ] || continue
      mkdir -p "$ws/$sub"
      for f in "$staging/$sub"/*; do
        [ -f "$f" ] || continue
        rel="$sub/$(basename "$f")"
        if [ -e "$ws/$rel" ]; then conflicts+=("$rel"); else cp "$f" "$ws/$rel" && copied+=("$rel"); fi
      done
    done
    jq -nc \
      --argjson copied "$(printf '%s\n' "${copied[@]:-}" | json_lines)" \
      --argjson conflicts "$(printf '%s\n' "${conflicts[@]:-}" | json_lines)" \
      '{copied:$copied, conflicts:$conflicts}'
    ;;
  *)
    echo '{"error":"unknown_command"}'; exit 1
    ;;
esac
