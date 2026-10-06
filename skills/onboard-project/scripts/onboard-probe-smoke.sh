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
today=$(date +%F)

out=$(probe init)
eq "slug derives from repo name" "$(jq -r .slug <<<"$out")" "my-shop-onboarding"
eq "no workspace yet" "$(jq -r .workspace_exists <<<"$out")" "false"
eq "no profile" "$(jq -r .profile_status <<<"$out")" "absent"
eq "signals found" "$(jq -c '[.signals|.manifests,.data,.apis,.ci,.tests,.docs|.count]' <<<"$out")" "[1,1,1,1,1,1]"
eq "absent area counts zero" "$(jq -r .signals.infra.count <<<"$out")" "0"
eq "config absent in base repo" "$(jq -r .signals.config.count <<<"$out")" "0"
eq "tracked_files counts git ls-files" "$(jq -r .tracked_files <<<"$out")" "6"
eq "repo name reported" "$(jq -r .repo <<<"$out")" "My_Shop"
eq "units reports a mode" "$(jq -r '.units|has("mode")' <<<"$out")" "true"
eq "units reports a units list" "$(jq -r '.units|has("units")' <<<"$out")" "true"
eq "facts_dir under the repo" "$(jq -r .facts_dir <<<"$out")" "$repo/.bf/onboard/my-shop-onboarding"
eq "sha is none before the first commit" "$(jq -r .sha <<<"$out")" "none"
eq "fresh_slug is dated" "$(jq -r .fresh_slug <<<"$out")" "my-shop-onboarding-$today"
git -C "$repo" -c user.email=smoke@example.com -c user.name=smoke commit -q -m init
eq "sha is the short HEAD once committed" "$(probe init | jq -r .sha)" "$(git -C "$repo" rev-parse --short HEAD)"

mkdir -p "$tmp/.bf/teach/my-shop-onboarding" "$tmp/.bf/teach/My_Shop-notes" "$tmp/.bf/teach/my-shop-onboarding-2026-01-02" "$tmp/.bf/teach/shop-extras" "$tmp/.bf/teach/my-shopping"
printf '# Learning Profile\n\nStatus: declined\n' > "$tmp/.bf/teach/LEARNING-PROFILE.md"
out=$(probe init)
eq "existing workspace detected" "$(jq -r .workspace_exists <<<"$out")" "true"
eq "similar workspaces match on name or name- prefix only, own slug excluded" \
  "$(jq -c .similar_workspaces <<<"$out")" '["My_Shop-notes","my-shop-onboarding-2026-01-02"]'
eq "declined profile read" "$(jq -r .profile_status <<<"$out")" "declined"
eq "slug override" "$(probe init custom | jq -r .slug)" "custom"
eq "slug override is slugified" "$(probe init 'My Course!' | jq -r .slug)" "my-course"
eq "traversal override is flattened" "$(probe init ../../evil | jq -r .slug)" "evil"
(cd "$repo" && HOME=$tmp bash "$script" init '../..' 2>&1) > "$tmp/empty.out" && rc=0 || rc=$?
eq "empty slug fails" "$rc:$(cat "$tmp/empty.out")" '1:{"error":"empty_slug"}'
printf '# Learning Profile\n\nStatus: active\n' > "$tmp/.bf/teach/LEARNING-PROFILE.md"
eq "active profile read" "$(probe init | jq -r .profile_status)" "active"
printf '# Learning Profile\n' > "$tmp/.bf/teach/LEARNING-PROFILE.md"
eq "profile without status is unknown" "$(probe init | jq -r .profile_status)" "unknown"
printf '# Learning Profile\n\nStatus: declined\n' > "$tmp/.bf/teach/LEARNING-PROFILE.md"

eq "fresh_slug first candidate" "$(probe init | jq -r .fresh_slug)" "my-shop-onboarding-$today"
mkdir -p "$tmp/.bf/teach/my-shop-onboarding-$today"
eq "fresh_slug skips a taken dated slug" "$(probe init | jq -r .fresh_slug)" "my-shop-onboarding-$today-2"
mkdir -p "$tmp/.bf/teach/my-shop-onboarding-$today-2"
eq "fresh_slug skips -2 as well" "$(probe init | jq -r .fresh_slug)" "my-shop-onboarding-$today-3"
rmdir "$tmp/.bf/teach/my-shop-onboarding-$today" "$tmp/.bf/teach/my-shop-onboarding-$today-2"

ws=$tmp/.bf/teach/my-shop-onboarding
mkdir -p "$ws/lessons" "$ws/reference"
printf '<a href="0001-intro.html">a</a> <a href="../reference/0001-cmds.html#run">b</a> <a href="https://x.io">c</a>\n' \
  > "$ws/lessons/0000-course-map.html"
touch "$ws/lessons/0001-intro.html"
eq "missing reference is broken" "$(probe verify "$ws" | jq -c .broken_links)" \
  '["lessons/0000-course-map.html -> ../reference/0001-cmds.html#run"]'
touch "$ws/reference/0001-cmds.html"
eq "all links resolve" "$(probe verify "$ws" | jq -c '[.lessons,.references,(.broken_links|length)]')" "[2,1,0]"

cat > "$ws/lessons/0001-intro.html" <<'HTML'
<img src="../img/a.png?v=2"> <a href='0002-gone.html#x'>q</a> <script src="app.js"></script> <a href="../reference/0001-cmds.html?x=1#y">r</a>
HTML
eq "single-quoted href, src and query/fragment handled" "$(probe verify "$ws" | jq -c .broken_links)" \
  '["lessons/0001-intro.html -> ../img/a.png?v=2","lessons/0001-intro.html -> 0002-gone.html#x","lessons/0001-intro.html -> app.js"]'

lessonless=$tmp/.bf/teach/no-lessons
mkdir -p "$lessonless"
(probe verify "$lessonless" 2>&1) > "$tmp/nl.out" && rc=0 || rc=$?
eq "verify without lessons dir errors" "$rc:$(jq -r .error "$tmp/nl.out")" "1:no_lessons_dir"
(probe bogus 2>&1) > "$tmp/uc.out" && rc=0 || rc=$?
eq "unknown command errors" "$rc:$(jq -r .error "$tmp/uc.out")" "1:unknown_command"

slug_of() {
  local d=$tmp/slugcase/$1
  mkdir -p "$d" && git init -q "$d"
  (cd "$d" && HOME=$tmp bash "$script" init | jq -r .slug)
}
eq "slugify collapses punctuation runs" "$(slug_of 'Foo__Bar..Baz')" "foo-bar-baz-onboarding"
eq "slugify trims edges" "$(slug_of '--Edge--')" "edge-onboarding"
eq "slugify falls back when nothing alphanumeric" "$(slug_of '___')" "repo-onboarding"

sig=$tmp/sigrepo
mkdir -p "$sig/docs" "$sig/app/config" "$sig/deploy" "$sig/k8s" "$sig/test"
touch "$sig/CONTRIBUTING.md" "$sig/docs/guide.md" "$sig/pom.xml" "$sig/Dockerfile.dev" "$sig/schema.prisma" \
  "$sig/user_repository.java" "$sig/svc.graphql" "$sig/openapi.yaml" "$sig/Jenkinsfile" "$sig/main.tf" "$sig/deploy/x.yaml" \
  "$sig/.env.local" "$sig/app/config/settings.yaml" "$sig/src-application-dev.yml" "$sig/application.properties" \
  "$sig/OrderTest.java" "$sig/test/a.py" "$sig/README.md"
git init -q "$sig" && git -C "$sig" add -A
sigout=$(cd "$sig" && HOME=$tmp bash "$script" init)
eq "docs regex" "$(jq -r .signals.docs.count <<<"$sigout")" "3"
eq "manifests regex" "$(jq -r .signals.manifests.count <<<"$sigout")" "2"
eq "data regex" "$(jq -r .signals.data.count <<<"$sigout")" "2"
eq "apis regex" "$(jq -r .signals.apis.count <<<"$sigout")" "2"
eq "ci regex" "$(jq -r .signals.ci.count <<<"$sigout")" "1"
eq "infra regex" "$(jq -r .signals.infra.count <<<"$sigout")" "2"
eq "config regex" "$(jq -r .signals.config.count <<<"$sigout")" "4"
eq "tests regex" "$(jq -r .signals.tests.count <<<"$sigout")" "2"

short=$tmp/api
mkdir -p "$short" "$tmp/.bf/teach/rapid-notes" "$tmp/.bf/teach/api-onboarding" "$tmp/.bf/teach/API-guide"
git init -q "$short"
eq "short repo name does not match substring workspaces" \
  "$(cd "$short" && HOME=$tmp bash "$script" init | jq -c .similar_workspaces)" '["API-guide"]'

(cd "$tmp" && HOME=$tmp bash "$script" init >/dev/null 2>&1) && rc=0 || rc=$?
eq "outside a repo fails" "$rc" "1"

[ "$fails" -eq 0 ]
