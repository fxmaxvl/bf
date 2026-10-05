#!/usr/bin/env bash
# Deterministic groundwork for onboard-project: workspace paths, prior-course detection, and the
# repo signals that decide which curriculum areas exist — one call instead of dozens of globs.
# Usage:
#   onboard-probe.sh init [slug]        # slug defaults to "<repo>-onboarding"
#   onboard-probe.sh verify <workspace> # lists lesson/reference links whose target file is missing
# Output: single-line JSON.
set -euo pipefail

command -v jq >/dev/null || { echo '{"error":"jq_not_found"}'; exit 1; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
teach_root="$HOME/.bf/teach"

slugify() { tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//'; }
json_lines() { { grep . || true; } | jq -R . | jq -sc .; }

# Lists are capped so a monorepo with 4k protos doesn't flood the context; counts stay exact.
signal() {
  printf '%s\n' "$files" | { grep -E "$1" || true; } | json_lines | jq -c '{count:length, sample:.[0:15]}'
}

case "${1:-init}" in
  init)
    root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo '{"error":"not_a_git_repo"}'; exit 1; }
    cd "$root"
    repo=$(basename "$root")
    base=$(printf '%s' "$repo" | slugify)
    slug=${2:-$base-onboarding}
    workspace="$teach_root/$slug"
    files=$(git ls-files)

    profile=absent
    if [ -f "$teach_root/LEARNING-PROFILE.md" ]; then
      profile=$(sed -n 's/^Status:[[:space:]]*\([a-z]*\).*/\1/p' "$teach_root/LEARNING-PROFILE.md" | head -1)
      [ -n "$profile" ] || profile=unknown
    fi

    similar=$( (ls -1 "$teach_root" 2>/dev/null || true) | LC_ALL=C sort | { grep -i -e "$repo" -e "$base" -F || true; } | { grep -v -x -F "$slug" || true; } | json_lines)

    jq -nc \
      --arg root "$root" --arg repo "$repo" --arg slug "$slug" --arg ws "$workspace" \
      --arg facts "$root/.bf/onboard/$slug" --arg profile "$profile" \
      --arg sha "$(git rev-parse --short HEAD 2>/dev/null || echo none)" \
      --argjson exists "$([ -d "$workspace" ] && echo true || echo false)" \
      --argjson similar "$similar" \
      --argjson tracked "$(printf '%s\n' "$files" | grep -c . || true)" \
      --argjson units "$(bash "$here/../../arch-audit/scripts/detect-units.sh" .)" \
      --argjson docs "$(signal '(^|/)(README|CONTRIBUTING|ARCHITECTURE|CLAUDE|AGENTS)[^/]*$|(^|/)(docs?|adrs?|decisions)/')" \
      --argjson manifests "$(signal '(^|/)(package\.json|pom\.xml|build\.gradle(\.kts)?|BUILD(\.bazel)?|MODULE\.bazel|WORKSPACE|go\.mod|Cargo\.toml|pyproject\.toml|requirements[^/]*\.txt|Gemfile|composer\.json|[^/]*\.csproj|Makefile|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml)$')" \
      --argjson data "$(signal '(^|/)(migrations?|db|schema|liquibase|flyway)/|\.sql$|schema\.prisma$|(^|/)[^/]*(entity|repository|dao)[^/]*\.[a-z]+$')" \
      --argjson apis "$(signal '\.proto$|(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$|\.graphqls?$|\.avsc$')" \
      --argjson ci "$(signal '^\.github/workflows/|^\.gitlab-ci\.yml$|(^|/)Jenkinsfile$|^\.circleci/|^\.buildkite/|^azure-pipelines\.yml$')" \
      --argjson infra "$(signal '\.tf$|(^|/)Chart\.yaml$|(^|/)(k8s|kubernetes|helm|deploy|infra)/')" \
      --argjson config "$(signal '(^|/)\.env[^/]*$|(^|/)(config|conf|settings)[^/]*\.(ya?ml|json|toml|properties|conf)$|application[^/]*\.(ya?ml|properties)$')" \
      --argjson tests "$(signal '(^|/)(tests?|__tests__|spec|it|e2e)/|[._-](test|spec)\.[a-z]+$|Test\.(java|scala|kt)$')" \
      '{root:$root, repo:$repo, sha:$sha, slug:$slug, workspace:$ws, workspace_exists:$exists,
        similar_workspaces:$similar, facts_dir:$facts, profile_status:$profile, tracked_files:$tracked,
        units:$units, signals:{docs:$docs, manifests:$manifests, data:$data, apis:$apis, ci:$ci,
        infra:$infra, config:$config, tests:$tests}}'
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
        [ -z "$target" ] && continue
        [ -f "$dir/$target" ] || broken+=("${page#"$ws"/} -> $href")
      done <<< "$(grep -oE 'href="[^"]+"' "$page" | sed 's/^href="//;s/"$//' | grep -vE '^(https?:|mailto:|#|file:)' || true)"
    done
    jq -nc \
      --argjson lessons "$(find "$ws/lessons" -name '*.html' | wc -l | tr -d ' ')" \
      --argjson references "$( (find "$ws/reference" -name '*.html' 2>/dev/null || true) | wc -l | tr -d ' ')" \
      --argjson broken "$(printf '%s\n' "${broken[@]:-}" | json_lines)" \
      '{lessons:$lessons, references:$references, broken_links:$broken}'
    ;;
  *)
    echo '{"error":"unknown_command"}'; exit 1
    ;;
esac
