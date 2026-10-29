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
eq "all links resolve" "$(probe verify "$ws" | jq -c '[.lessons,.references,(.broken_links|length)]')" "[1,1,0]"

cat > "$ws/lessons/0001-intro.html" <<'HTML'
<img src="../img/a.png?v=2"> <a href='0002-gone.html#x'>q</a> <script src="app.js"></script> <a href="../reference/0001-cmds.html?x=1#y">r</a>
HTML
eq "single-quoted href, src and query/fragment handled" "$(probe verify "$ws" | jq -c .broken_links)" \
  '["lessons/0001-intro.html -> ../img/a.png?v=2","lessons/0001-intro.html -> 0002-gone.html#x","lessons/0001-intro.html -> app.js"]'

cat > "$ws/lessons/0001-intro.html" <<'HTML'
<p>See <a href="0009-missing.html">next</a>.</p>
<pre><code>&lt;a href="quoted-template.html"&gt;x&lt;/a&gt;
<img src="also-quoted.png"></code></pre>
<p>Inline <code>&lt;link href="inline.css"&gt;</code> too.</p>
HTML
eq "links quoted in pre/code are ignored, real ones still checked" "$(probe verify "$ws" | jq -c .broken_links)" \
  '["lessons/0001-intro.html -> 0009-missing.html"]'

lessonless=$tmp/.bf/teach/no-lessons
mkdir -p "$lessonless"
st=$tmp/staging; pws=$tmp/promoted
mkdir -p "$st/lessons" "$st/reference" "$pws/lessons"
echo new > "$st/lessons/0001-a.html"; echo new > "$st/reference/0001-r.html"; echo new > "$st/lessons/0002-b.html"
echo keep > "$pws/lessons/0002-b.html"
eq "promote copies staged pages and reports a conflict" "$(probe promote "$st" "$pws" | jq -c '[.copied,.conflicts]')" \
  '[["lessons/0001-a.html","reference/0001-r.html"],["lessons/0002-b.html"]]'
eq "promote never overwrites an existing page" "$(cat "$pws/lessons/0002-b.html"):$(cat "$pws/reference/0001-r.html")" "keep:new"
(probe promote "$tmp/no-such-staging" "$pws" 2>&1) > "$tmp/ns.out" && rc=0 || rc=$?
eq "promote without a staging dir errors" "$rc:$(jq -r .error "$tmp/ns.out")" "1:no_staging_dir"

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

bp() { local d=$1; shift; (cd "$d" && HOME=$tmp bash "$script" brief "$@"); }
bperr() { local d=$1; shift; (bp "$d" "$@" 2>&1) > "$tmp/bp.out" && rc=0 || rc=$?; echo "$rc:$(jq -r .error "$tmp/bp.out")"; }

b=$(bp "$repo")
eq "brief identity fields" "$(jq -r '[.repo,.path,.output_name]|join("|")' <<<"$b")" "My_Shop||my-shop.md"
eq "brief output_path is absolute under the repo" "$(jq -r .output_path <<<"$b")" "$(cd "$repo" && pwd -P)/.bf/onboard-brief/my-shop.md"
eq "brief sha is the short HEAD" "$(jq -r .sha <<<"$b")" "$(git -C "$repo" rev-parse --short HEAD)"
eq "brief tracked_files is exact" "$(jq -r .tracked_files <<<"$b")" "6"
eq "brief omits the course-workspace fields" \
  "$(jq -c '[has("slug"),has("workspace"),has("fresh_slug"),has("similar_workspaces"),has("facts_dir"),has("profile_status")]|unique' <<<"$b")" "[false]"
eq "brief . is a whole-repo run" "$(bp "$repo" . | jq -r '[.path,.output_name]|join("|")')" "|my-shop.md"
eq "brief .. from a subdirectory is a whole-repo run" "$(bp "$repo/src" .. | jq -r '[.path,.output_name]|join("|")')" "|my-shop.md"
eq "brief with no path from a subdirectory is a whole-repo run" "$(bp "$repo/src" | jq -r '[.path,.output_name,.tracked_files]|join("|")')" "|my-shop.md|6"
b=$(bp "$repo/src" ../db)
eq "brief relative path from a subdirectory" "$(jq -r '[.path,.output_name,.tracked_files]|join("|")' <<<"$b")" "db|my-shop--db.md|1"
mkdir -p "$repo/#odd dir's (x)" && echo x > "$repo/#odd dir's (x)/f.txt" && git -C "$repo" add -A >/dev/null
odd="#odd dir's (x)"
eq "brief - reads a metacharacter path from stdin" \
  "$(cd "$repo" && printf '%s\n' "$odd" | HOME=$tmp bash "$script" brief - | jq -r '[.path,.tracked_files]|join("|")')" "$odd|1"
eq "brief - with empty stdin is a whole-repo run" "$(cd "$repo/src" && printf '\n' | HOME=$tmp bash "$script" brief - | jq -r '[.path,.output_name]|join("|")')" "|my-shop.md"
git -C "$repo" rm -rq --cached "#odd dir's (x)" && rm -rf "$repo/#odd dir's (x)"
eq "brief path outside the repo is rejected" "$(bperr "$repo" /)" "1:path_outside_repo"
eq "brief missing path is rejected" "$(bperr "$repo" nope)" "1:not_a_directory"

rk=$tmp/rank
mkdir -p "$rk/api" "$rk/Docs"
touch "$rk/api/package.json" "$rk/Docs/README.md" "$rk/package.json" "$rk/README.md"
git init -q "$rk" && git -C "$rk" add -A
b=$(bp "$rk")
eq "brief ranks root manifests first" "$(jq -r '.signals.manifests.sample[0]' <<<"$b")" "package.json"
eq "brief ranks the root README first" "$(jq -r '.signals.docs.sample[0]' <<<"$b")" "README.md"
eq "brief keeps signal counts exact" "$(jq -c '[.signals.manifests.count,.signals.docs.count]' <<<"$b")" "[2,2]"
eq "brief reports all eight signals" "$(jq -c '.signals|keys' <<<"$b")" '["apis","ci","config","data","docs","infra","manifests","tests"]'

eq "brief dir-mode fallback reports layout dir" "$(bp "$repo" | jq -r '[.units.mode,.layout,.units.count]|join("|")')" "dir|dir|3"

big=$tmp/big
mkdir -p "$big/tool1" "$big/tool2" "$big/svc2/g1/u1" "$big/svc2/g1/u2"
touch "$big/tool1/package.json" "$big/tool2/package.json" "$big/svc2/g1/u1/package.json" "$big/svc2/g1/u2/package.json"
for i in $(seq -w 1 35); do mkdir -p "$big/svc/s$i"; touch "$big/svc/s$i/package.json"; done
git init -q "$big" && git -C "$big" add -A
b=$(bp "$big")
eq "brief build mode counts every unit and caps the sample" \
  "$(jq -c '[.units.mode,.units.count,(.units.sample|length),(.units.shown|length)]' <<<"$b")" '["build",39,30,8]'
eq "brief by_top_dir sums to the exact count" "$(jq -c '(.units.by_top_dir|[.[]]|add) == .units.count' <<<"$b")" "true"
eq "brief buckets depth-1 units under (top-level)" "$(jq -c .units.by_top_dir <<<"$b")" '{"(top-level)":2,"svc":35,"svc2":2}'
eq "brief groups subtract the shown units and omit empty groups" \
  "$(jq -c '.units.groups|map({dir,remaining})' <<<"$b")" '[{"dir":"svc","remaining":29},{"dir":"svc2","remaining":2}]'
eq "brief group examples come from sample[8:30], at most 3" \
  "$(jq -c '.units.groups|map(.examples)' <<<"$b")" '[["s07","s08","s09"],[]]'
eq "brief build layout starts the agent past 30 units" "$(jq -c '[.layout,.needs_agent]' <<<"$b")" '["build",true]'
eq "brief by_top_dir keys are repo-root-relative" "$(bp "$big" svc2 | jq -c '[.units.count,.units.by_top_dir,(.units.groups|map(.dir)),.units.sample[0].path]')" '[2,{"svc2/g1":2},[],"svc2/g1/u1"]'
eq "brief scoped tracked_files counts the subtree" "$(bp "$big" svc | jq -c '[.tracked_files,.units.by_top_dir]')" '[35,{"(top-level)":35}]'

ci=$tmp/ci
mkdir -p "$ci/.github/workflows" "$ci/app"
touch "$ci/.github/workflows/build.yml" "$ci/app/package.json"
git init -q "$ci" && git -C "$ci" add -A
eq "brief scoped run still reports root CI from the whole repo" "$(bp "$ci" app | jq -c '[.tracked_files,.signals.ci.count,.signals.ci.sample[0]]')" '[1,1,".github/workflows/build.yml"]'

many=$tmp/many
mkdir -p "$many/pile"
(cd "$many/pile" && seq 1 2001 | sed 's/^/f/' | xargs touch)
git init -q "$many" && git -C "$many" add -A
eq "brief no agent past 2000 files when there are no groups" "$(bp "$many" | jq -c '[.tracked_files,.units.count,.needs_agent]')" "[2001,1,false]"

flat=$tmp/flat
mkdir -p "$flat" && touch "$flat/package.json" "$flat/main.js"
git init -q "$flat" && git -C "$flat" add -A
eq "brief flat repo" "$(bp "$flat" | jq -c '[.layout,.units.count,.needs_agent]')" '["flat",0,false]'
empty=$tmp/empty
git init -q "$empty"
eq "brief empty repo" "$(bp "$empty" | jq -c '[.layout,.tracked_files,.sha]')" '["empty",0,"none"]'
single=$tmp/single
mkdir -p "$single/app" && touch "$single/app/package.json"
git init -q "$single" && git -C "$single" add -A
eq "brief single build unit" "$(bp "$single" | jq -c '[.layout,.units.mode,.units.count]')" '["single","build",1]'

hot=$tmp/hot
mkdir -p "$hot/src/a" "$hot/src/b" "$hot/docs" "$hot/d1" "$hot/d2" "$hot/d3" "$hot/d4" "$hot/d5"
touch "$hot/src/a/x" "$hot/src/a/y" "$hot/src/b/z" "$hot/docs/q" "$hot/rootfile" "$hot/d1/f" "$hot/d2/f" "$hot/d3/f" "$hot/d4/f" "$hot/d5/f"
git init -q "$hot" && git -C "$hot" add -A
git -C "$hot" -c user.email=smoke@example.com -c user.name=smoke commit -q -m one
echo more > "$hot/src/a/x" && git -C "$hot" add -A
git -C "$hot" -c user.email=smoke@example.com -c user.name=smoke commit -q -m two
eq "brief hot_dirs is a capped top-level array ordered by files touched" "$(bp "$hot" | jq -c .hot_dirs)" '["src/a","d1","d2","d3","d4"]'
eq "brief hot_dirs is repo-root-relative" "$(bp "$hot" src | jq -c .hot_dirs)" '["src/a","src/b"]'
gone=$tmp/gone
mkdir -p "$gone/old/x" "$gone/new" && touch "$gone/old/x/f" "$gone/old/x/g" "$gone/new/h"
git init -q "$gone" && git -C "$gone" add -A
git -C "$gone" -c user.email=smoke@example.com -c user.name=smoke commit -q -m one
git -C "$gone" rm -rq old && git -C "$gone" -c user.email=smoke@example.com -c user.name=smoke commit -q -m two
eq "brief hot_dirs skips directories no longer in the tree" "$(bp "$gone" | jq -c .hot_dirs)" '["new"]'
eq "brief hot_dirs is empty without commits" "$(bp "$empty" | jq -c .hot_dirs)" "[]"

(cd "$tmp" && HOME=$tmp bash "$script" init >/dev/null 2>&1) && rc=0 || rc=$?
eq "outside a repo fails" "$rc" "1"

[ "$fails" -eq 0 ]
