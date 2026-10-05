#!/usr/bin/env bash
# Smoke test for host-rules.sh against throwaway git repos.
#
# Usage: host-rules-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host-rules.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

run() { (cd "$1" && bash "$script"); }

empty=$tmp/empty
git init -q "$empty"
echo '# readme' > "$empty/README.md"
eq "no rule files -> []" "$(run "$empty")" '[]'

repo=$tmp/repo
git init -q "$repo"
mkdir -p "$repo/.github" "$repo/.agents/instructions/sub" "$repo/docs"
echo r > "$repo/Review.md"
echo c > "$repo/.github/CONTRIBUTING.md"
echo x > "$repo/.agents/instructions/sub/x.md"
echo d > "$repo/docs/CLAUDE.md"
echo r > "$repo/README.md"
eq "mixed case, github, nested; non-rule files skipped" \
  "$(run "$repo" | jq -c --arg r "$repo" 'map(sub($r + "/"; ""))')" \
  '[".agents/instructions/sub/x.md",".github/CONTRIBUTING.md","Review.md"]'
eq "Review.md listed once" "$(run "$repo" | jq '[.[]|select(test("(?i)review\\.md$"))]|length')" 1

links=$tmp/links
git init -q "$links"
mkdir -p "$links/docs"
echo a > "$links/docs/AGENTS.md"
ln -s docs/AGENTS.md "$links/AGENTS.md"
ln -s AGENTS.md "$links/CLAUDE.md"
eq "symlinked rule files keep in-repo names" \
  "$(run "$links" | jq -c --arg r "$links" 'map(sub($r + "/"; ""))')" '["AGENTS.md","CLAUDE.md"]'

ln -s missing.md "$links/REVIEW.md"
set +e; out=$(run "$links"); rc=$?; set -e
eq "dangling link skipped" "$(jq -c 'length' <<< "$out")" 2
eq "dangling link sorted last still exits 0" "$rc" 0

outside=$tmp/outside
mkdir "$outside"
set +e
out=$(cd "$outside" && GIT_CEILING_DIRECTORIES=$tmp bash "$script"); rc=$?
set -e
eq "outside a git repo -> error, exit 1" "$(jq -r .error <<<"$out"):$rc" not_a_git_repo:1

[ "$fails" -eq 0 ]
