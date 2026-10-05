#!/usr/bin/env bash
# Smoke test for onboard-probe.sh against a throwaway repo and a throwaway HOME.
#
# Usage: onboard-probe-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/onboard-probe.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

repo=$tmp/My_Shop
mkdir -p "$repo/db/migrations" "$repo/api" "$repo/.github/workflows" "$repo/src"
touch "$repo/package.json" "$repo/db/migrations/001_init.sql" "$repo/api/orders.proto" \
  "$repo/.github/workflows/ci.yml" "$repo/README.md" "$repo/src/cart.test.ts"
git init -q "$repo" && git -C "$repo" add -A

probe() { (cd "$repo" && HOME=$tmp bash "$script" "$@"); }

out=$(probe init)
eq "slug derives from repo name" "$(jq -r .slug <<<"$out")" "my-shop-onboarding"
eq "no workspace yet" "$(jq -r .workspace_exists <<<"$out")" "false"
eq "no profile" "$(jq -r .profile_status <<<"$out")" "absent"
eq "signals found" "$(jq -c '[.signals|.manifests,.data,.apis,.ci,.tests,.docs|.count]' <<<"$out")" "[1,1,1,1,1,1]"
eq "absent area counts zero" "$(jq -r .signals.infra.count <<<"$out")" "0"

mkdir -p "$tmp/.bf/teach/my-shop-onboarding" "$tmp/.bf/teach/My_Shop-notes" "$tmp/.bf/teach/my-shop-onboarding-2026-01-02"
printf '# Learning Profile\n\nStatus: declined\n' > "$tmp/.bf/teach/LEARNING-PROFILE.md"
out=$(probe init)
eq "existing workspace detected" "$(jq -r .workspace_exists <<<"$out")" "true"
eq "similar workspaces match raw and slugified name, own slug excluded" \
  "$(jq -c .similar_workspaces <<<"$out")" '["My_Shop-notes","my-shop-onboarding-2026-01-02"]'
eq "declined profile read" "$(jq -r .profile_status <<<"$out")" "declined"
eq "slug override" "$(probe init custom | jq -r .slug)" "custom"

ws=$tmp/.bf/teach/my-shop-onboarding
mkdir -p "$ws/lessons" "$ws/reference"
printf '<a href="0001-intro.html">a</a> <a href="../reference/0001-cmds.html#run">b</a> <a href="https://x.io">c</a>\n' \
  > "$ws/lessons/0000-course-map.html"
touch "$ws/lessons/0001-intro.html"
eq "missing reference is broken" "$(probe verify "$ws" | jq -c .broken_links)" \
  '["lessons/0000-course-map.html -> ../reference/0001-cmds.html#run"]'
touch "$ws/reference/0001-cmds.html"
eq "all links resolve" "$(probe verify "$ws" | jq -c '[.lessons,.references,(.broken_links|length)]')" "[2,1,0]"

(cd "$tmp" && HOME=$tmp bash "$script" init >/dev/null 2>&1) && rc=0 || rc=$?
eq "outside a repo fails" "$rc" "1"

[ "$fails" -eq 0 ]
