#!/usr/bin/env bash
# Smoke test for resolve-conventions.sh and discover-conventions.sh against a throwaway HOME/repo.
#
# Usage: resolve-conventions-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
resolve=$dir/resolve-conventions.sh
discover=$dir/discover-conventions.sh
plugin_conv=$(cd "$dir/../../.." && pwd)/conventions
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

home=$tmp/home
repo=$tmp/repo
mkdir -p "$home/.bf/conventions" "$repo/.bf/conventions"
git init -q "$repo"
echo '# project dev' > "$repo/.bf/conventions/dev.md"
echo '# user dev' > "$home/.bf/conventions/dev.md"
echo '# user only' > "$home/.bf/conventions/mine.md"
echo '# user git' > "$home/.bf/conventions/git.md"
[ -f "$plugin_conv/testing.md" ] || { echo "FAIL setup: $plugin_conv/testing.md missing"; exit 1; }

in_repo() { (cd "$repo" && HOME=$home "$@"); }

r=$(in_repo bash "$resolve" dev mine testing nothing-here)
eq "project beats user" "$(jq -r .dev <<<"$r")" "$repo/.bf/conventions/dev.md"
eq "user beats plugin / user only" "$(jq -r .mine <<<"$r")" "$home/.bf/conventions/mine.md"
eq "plugin tier" "$(jq -r .testing <<<"$r")" "$plugin_conv/testing.md"
eq "unknown -> null" "$(jq -c '.["nothing-here"]' <<<"$r")" null
eq "user beats plugin" "$(in_repo bash "$resolve" git | jq -r .git)" "$home/.bf/conventions/git.md"
eq ".md suffix accepted" "$(in_repo bash "$resolve" dev.md | jq -c 'keys')" '["dev"]'

set +e
u=$(in_repo bash "$resolve"); rc=$?
set -e
eq "no args -> usage exit 1" "$(jq -r .error <<<"$u"):$rc" usage:1

outside=$tmp/outside
mkdir "$outside"
eq "outside a git repo -> user tier" \
  "$(cd "$outside" && HOME=$home GIT_CEILING_DIRECTORIES=$tmp bash "$resolve" dev | jq -r .dev)" "$home/.bf/conventions/dev.md"

qhome="$tmp/ho\"me"
mkdir -p "$qhome/.bf/conventions"
echo '# q' > "$qhome/.bf/conventions/q.md"
eq "quote in HOME is escaped" \
  "$(cd "$outside" && HOME=$qhome GIT_CEILING_DIRECTORIES=$tmp bash "$resolve" q | jq -r .q)" "$qhome/.bf/conventions/q.md"

d=$(in_repo bash "$discover")
eq "discover lists project+user, project wins" \
  "$(jq -c '[.[]|[.filename,.tier,.first_heading]]' <<<"$d")" \
  '[["dev.md","project","# project dev"],["git.md","user","# user git"],["mine.md","user","# user only"]]'
eq "discover honours PROJECT_ROOT argument" \
  "$(cd "$outside" && HOME=$home bash "$discover" "$repo" | jq -c '[.[]|.tier]|unique')" '["project","user"]'

[ "$fails" -eq 0 ]
