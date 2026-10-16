#!/usr/bin/env bash
# Smoke test for the bf:visualize scripts. Network cases print SKIP when the pinned likec4 cannot be fetched.
#
# Usage: visualize-smoke.sh
#        BF_VIZ_SMOKE_CACHE=<dir> keeps a warm likec4 cache across runs (default: a throwaway dir).
# Output: one PASS/FAIL/SKIP line per case; exit 0 when no case fails, 1 otherwise.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill=$(cd "$here/.." && pwd)
plugin=$(cd "$here/../../.." && pwd)
fx=$here/fixtures
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

home=$tmp/home
repo=$tmp/repo
mkdir -p "$home" "$repo"
git init -q "$repo"
in_repo() { (cd "$repo" && HOME=$home "$@"); }

paths=$here/viz-paths.sh
vp() { HOME=$home bash "$paths" "$@"; }
vpf() { HOME=$home GIT_CEILING_DIRECTORIES=$tmp bash "$paths" "$@"; }
field() { jq -r ".$1" <<<"$2"; }
err_of() { local out rc; out=$("$@" 2>&1); rc=$?; echo "$(jq -r '.error // "none"' <<<"$out"):$rc"; }

design_body() {
  printf '# Acme\n\n## Summary\nx\n\n## Actors & systems\n%s\n\n## Proposed design\ny\n' "$1"
}

mkdir -p "$repo/docs" "$repo/.bf/audits" "$repo/notes"
design_body '- user' > "$repo/docs/acme-design.md"
design_body '- user' > "$repo/docs/acme-design-2.md"
design_body '- user' > "$repo/docs/notes.md"
printf '# readme\n' > "$repo/docs/readme.md"
printf '# audit\n' > "$repo/.bf/audits/acme-arch-audit.md"
printf '# audit\n' > "$repo/notes/x-arch-audit.md"

r=$(vp "$repo/docs/acme-design.md")
eq "design: kind" "$(field kind "$r")" design
eq "design: slug" "$(field slug "$r")" acme
eq "design: doc is absolute" "$(field doc "$r")" "$repo/docs/acme-design.md"
eq "design-N: slug" "$(field slug "$(vp "$repo/docs/acme-design-2.md")")" acme-2
r=$(vp "$repo/docs/notes.md")
eq "content fallback: kind" "$(field kind "$r")" design
eq "content fallback: stem slug" "$(field slug "$r")" notes
eq "unsupported input" "$(err_of vp "$repo/docs/readme.md")" unsupported_input:1
eq "missing arg" "$(err_of vp)" missing_arg:1
eq "doc not found" "$(err_of vp "$repo/docs/nope.md")" doc_not_found:1
r=$(vp "$repo/.bf/audits/acme-arch-audit.md")
eq "arch-audit: kind" "$(field kind "$r")" arch-audit
eq "arch-audit: slug" "$(field slug "$r")" acme-arch

r=$(cd "$tmp" && vp "$repo/docs/acme-design.md")
eq "design: project_root from doc, not cwd" "$(field project_root "$r")" "$repo"
eq "design: in_git" "$(field in_git "$r")" true
eq "design: model next to doc" "$(field model_path "$r")" "$repo/docs/acme.c4"
eq "design: build_dir" "$(field build_dir "$r")" "$repo/.bf/visualize/acme"
eq "design: html_path" "$(field html_path "$r")" "$repo/.bf/visualize/acme/index.html"
eq "design: mapping_path" "$(field mapping_path "$r")" "$repo/.bf/visualize/acme/mapping.md"
eq "design: model_exists false" "$(field model_exists "$r")" false
touch "$repo/docs/acme.c4"
eq "design: model_exists true" "$(field model_exists "$(vp "$repo/docs/acme-design.md")")" true
rm "$repo/docs/acme.c4"
eq "design: nothing created" "$([ -e "$repo/.bf/visualize" ] && echo yes || echo no)" no

r=$(cd "$tmp" && vp "$repo/.bf/audits/acme-arch-audit.md")
eq "arch-audit: root is parent of .bf/audits" "$(field project_root "$r")" "$repo"
eq "arch-audit: model under docs/architecture" "$(field model_path "$r")" "$repo/docs/architecture/acme-arch.c4"
eq "arch-audit elsewhere: git root" "$(field project_root "$(vp "$repo/notes/x-arch-audit.md")")" "$repo"

mkdir -p "$tmp/elsewhere/.bf/audits"
design_body '- user' > "$tmp/elsewhere/acme-design.md"
printf '# a\n' > "$tmp/elsewhere/x-arch-audit.md"
printf '# a\n' > "$tmp/elsewhere/.bf/audits/y-arch-audit.md"
r=$(vpf "$tmp/elsewhere/acme-design.md")
eq "outside git: in_git false" "$(field in_git "$r")" false
eq "outside git: build under HOME" "$(field build_dir "$r")" "$home/.bf/visualize/acme"
eq "outside git: model next to doc" "$(field model_path "$r")" "$tmp/elsewhere/acme.c4"
eq "outside git: arch-audit outside .bf/audits" "$(err_of vpf "$tmp/elsewhere/x-arch-audit.md")" no_project_root:1
eq "outside git: arch-audit root from path" "$(field project_root "$(vpf "$tmp/elsewhere/.bf/audits/y-arch-audit.md")")" "$tmp/elsewhere"

printf '# A\n\n## Summary\nx\n\n## Actors & systems\n\n\n## Proposed design\ny\n' > "$repo/docs/empty-design.md"
printf '# A\n\n## Summary\nx\n\n## Proposed design\ny\n\n## Actors & systems\n\n' > "$repo/docs/eof-design.md"
printf '# A\n\n## Summary\nx\n\n## Actors & systems\n   \n## Proposed design\ny\n' > "$repo/docs/empty-notes.md"
eq "empty actors: error" "$(err_of vp "$repo/docs/empty-design.md")" nothing_to_visualize:1
eq "empty actors at EOF: error" "$(err_of vp "$repo/docs/eof-design.md")" nothing_to_visualize:1
eq "empty actors, content-detected: error" "$(err_of vp "$repo/docs/empty-notes.md")" nothing_to_visualize:1
eq "empty actors: no .c4 written" "$(ls "$repo/docs"/*.c4 2>/dev/null | wc -l | tr -d ' ')" 0

rs=$here/resolve-spec.sh
base_spec=$skill/references/base-spec.c4
mkdir -p "$home/.bf/conventions" "$repo/.bf/conventions"
rsj() { in_repo bash "$rs" "$@"; }
r=$(rsj "$repo")
eq "resolve-spec: none -> override null" "$(jq -c .override <<<"$r")" null
eq "resolve-spec: base path" "$(field base "$r")" "$base_spec"
echo 'specification { element a_kind }' > "$home/.bf/conventions/visualize-spec.c4"
eq "resolve-spec: user tier" "$(field override_tier "$(rsj "$repo")")" user
echo 'specification { element b_kind }' > "$repo/.bf/conventions/visualize-spec.c4"
r=$(rsj "$repo")
eq "resolve-spec: project beats user" "$(field override_tier "$r"):$(field override "$r")" "project:$repo/.bf/conventions/visualize-spec.c4"
eq "resolve-spec: empty root never picks project (cwd inside repo)" "$(field override_tier "$(rsj "")")" user
rm "$home/.bf/conventions/visualize-spec.c4"
eq "resolve-spec: empty root, no user override -> null" "$(jq -c .override <<<"$(rsj "")")" null
rm "$repo/.bf/conventions/visualize-spec.c4"
eq "resolve-spec: no arg -> usage" "$(err_of rsj)" usage:1

inst=$here/install-likec4.sh
V=$(bash "$inst" --print-version)
eq "install: --print-version" "$([ -n "$V" ] && echo set)" set
mkdir -p "$tmp/nonode" "$tmp/shim"
ln -s "$(command -v jq)" "$tmp/nonode/jq"
eq "install: no node -> no_node" "$(err_of env PATH="$tmp/nonode:/usr/bin:/bin" BF_LIKEC4_CACHE_DIR="$tmp/c-nonode" bash "$inst")" no_node:1
fake_npm() { printf '#!/bin/sh\necho "%s" >&2\nexit 1\n' "$1" > "$tmp/shim/npm"; chmod +x "$tmp/shim/npm"; }
inst_fake() { env PATH="$tmp/shim:$PATH" BF_LIKEC4_CACHE_DIR="$tmp/c-fake" bash "$inst"; }
fake_npm 'npm error code ETARGET'
out=$(inst_fake 2>&1); eq "install: ETARGET -> mirror_lag" "$(jq -r .error <<<"$out")" mirror_lag
eq "install: mirror_lag names the pinned version" "$(jq -r .detail <<<"$out" | grep -cF "likec4@$V")" 1
fake_npm 'npm error code E404'
eq "install: E404 -> mirror_lag" "$(err_of inst_fake)" mirror_lag:1
fake_npm 'npm error something else broke'
eq "install: other failure -> install_failed" "$(err_of inst_fake)" install_failed:1
rm -f "$tmp/shim/npm"
eq "install: failed install leaves no cache dir" "$([ -e "$tmp/c-fake/likec4@$V" ] && echo yes || echo no)" no

online=false
npm view "likec4@$V" version >/dev/null 2>&1 && online=true
cache=${BF_VIZ_SMOKE_CACHE:-$tmp/cache}
net_skip() { echo "SKIP $1: offline"; }
if [ "$online" = true ]; then
  r=$(BF_LIKEC4_CACHE_DIR=$cache bash "$inst" 2>&1)
  bin=$(field bin "$r")
  eq "install 1a: reports pinned version" "$(field version "$r"):$("$bin" --version 2>&1 | grep -cF "$V")" "$V:1"
  touch "$(field cache_dir "$r")/.reuse-marker"
  BF_LIKEC4_CACHE_DIR=$cache bash "$inst" >/dev/null 2>&1
  eq "install 1b: second call reuses the cache" "$([ -e "$(field cache_dir "$r")/.reuse-marker" ] && echo kept || echo wiped)" kept
  : > "$(field cache_dir "$r")/node_modules/likec4/bin/likec4.mjs"
  r2=$(BF_LIKEC4_CACHE_DIR=$cache bash "$inst" 2>&1)
  eq "install 1c: corrupt cache is wiped and reinstalled" "$(field version "$r2"):$([ -e "$(field cache_dir "$r")/.reuse-marker" ] && echo kept || echo wiped)" "$V:wiped"
else
  net_skip "install 1a/1b/1c"
fi

co=$here/classify-output.sh
logs=$fx/logs
echo '[]' > "$tmp/allow-empty.json"
co_run() { bash "$co" "$1" --allowlist "${2:-$tmp/allow-empty.json}"; }
r=$(co_run "$logs/nested-validate.log")
eq "classify: nested-validate warning" "$(jq -c '[.warnings, .errors]' <<<"$r")" '[["Sequence view does not support nested actors"],[]]'
r=$(co_run "$logs/bad-ref.log")
eq "classify: bad-ref has one error" "$(jq '.errors | length' <<<"$r")" 1
eq "classify: bad-ref file basename" "$(basename "$(jq -r '.errors[0].file' <<<"$r")")" model.c4
eq "classify: bad-ref detail lines" "$(jq '.errors[0].lines | length' <<<"$r")" 2
eq "classify: bad-ref summary dropped, no warnings" "$(jq -c .warnings <<<"$r")" '[]'
r=$(co_run "$logs/clean-build.log")
eq "classify: empty allowlist denies vite chatter" "$(jq '.warnings | length' <<<"$r")" 5
printf '[%s]' '"^transforming\\.\\.\\.$"' > "$tmp/allow-one.json"
eq "classify: allowlisted bare line is dropped" "$(jq '.warnings | length' <<<"$(co_run "$logs/clean-build.log" "$tmp/allow-one.json")")" 4
printf '12:00:00.000 \033[1mWARN\033[0m  likec4 something odd\n' > "$tmp/warn.log"
eq "classify: timestamped WARN is a failure" "$(jq '.warnings | length' <<<"$(co_run "$tmp/warn.log")")" 1
printf '12:00:00.000 INFO  likec4 fine\n12:00:00.001 DEBUG likec4 fine\n' > "$tmp/info.log"
eq "classify: INFO and DEBUG pass" "$(jq -c . <<<"$(co_run "$tmp/info.log")")" '{"errors":[],"warnings":[]}'
eq "classify: missing log" "$(err_of co_run "$tmp/nope.log")" log_not_found:1
eq "classify: missing --allowlist is a usage error" "$(err_of bash "$co" "$logs/clean-build.log")" usage:1
eq "classify: --allowlist without a value fails fast" "$(err_of perl -e 'alarm 10; exec @ARGV' bash "$co" "$logs/clean-build.log" --allowlist)" usage:1

if [ "$online" = true ]; then
  BF_LIKEC4_CACHE_DIR=$cache bash "$inst" | jq -c .allowlist > "$tmp/allow-real.json"
  eq "classify: clean-build.log has no warnings under the real allowlist" "$(jq -c .warnings <<<"$(co_run "$logs/clean-build.log" "$tmp/allow-real.json")")" '[]'
  eq "classify: nested-actors warning survives the real allowlist" "$(jq -c .warnings <<<"$(co_run "$logs/nested-build.log" "$tmp/allow-real.json")")" '["Sequence view does not support nested actors"]'
else
  net_skip "real allowlist"
fi

cf=$here/c4-facts.sh
r=$(bash "$cf" "$fx/spike/model.c4")
eq "c4-facts: spike model" "$(jq -c '[.has_specification, .kinds, .views, .element_count, .tbd_count]' <<<"$r")" '[true,["system","container","component"],["index","shop","checkout"],7,0]'
r=$(bash "$cf" "$fx/c4-facts-edge.c4")
eq "c4-facts: edge fixture ignores comments, strings and the stamped marker" "$(jq -c '[.has_specification, .kinds, .views, .element_count, .tbd_count]' <<<"$r")" '[false,[],["index","shop","checkout"],3,1]'
r=$(bash "$cf" "$fx/shop.c4")
eq "c4-facts: shop" "$(jq -c '[.has_specification, .views, .element_count, .tbd_count]' <<<"$r")" '[false,["index","shop","checkout"],8,1]'
eq "c4-facts: missing file" "$(err_of bash "$cf" "$tmp/nope.c4")" file_not_found:1

bs() { in_repo env BF_LIKEC4_CACHE_DIR="$cache" bash "$here/build.sh" "$@"; }
j() { jq -r "$1" <<<"$2"; }
newdoc() { design_body '- user' > "$repo/docs/$1-design.md"; echo "$repo/docs/$1-design.md"; }
bdir() { echo "$repo/.bf/visualize/$1"; }
MARKER='// bf:visualize: FAILED VALIDATION — see diagnostics from the last run; fix and re-run /bf:visualize'

eq "build: no args -> usage" "$(err_of bs)" usage:1
eq "build: --doc without path -> usage" "$(err_of bs --doc)" usage:1
eq "build: --init without doc -> usage" "$(err_of bs --init)" usage:1
eq "build: --attempt is not accepted" "$(err_of bs --attempt 2 --doc "$repo/docs/acme-design.md")" usage:1

eq "init: nothing_to_visualize relayed" "$(err_of bs --init --doc "$repo/docs/empty-design.md")" nothing_to_visualize:1
eq "init: nothing_to_visualize creates no build dir" "$([ -e "$(bdir empty)" ] && echo yes || echo no)" no

d=$(newdoc ini); b=$(bdir ini); mkdir -p "$b"; echo stale > "$b/index.html"; echo stale > "$b/mapping.md"
r=$(bs --init --doc "$d")
eq "init: prints paths JSON" "$(j .slug "$r"):$(j .model_path "$r")" "ini:$repo/docs/ini.c4"
eq "init: state file" "$(jq -c . "$b/.run-state.json")" '{"attempts":0,"model_existed":false}'
eq "init: stale index.html and mapping.md deleted" "$([ -e "$b/index.html" ] || [ -e "$b/mapping.md" ] && echo left || echo gone)" gone

d=$(newdoc noinit)
eq "attempt without init -> not_initialized" "$(err_of bs --doc "$d")" not_initialized:1

d=$(newdoc nomodel); bs --init --doc "$d" >/dev/null
r=$(bs --doc "$d")
eq "pre-check: missing model" "$(jq -c '[.ok, .source, .retryable, .attempt, .final]' <<<"$r")" '[false,"staging",false,1,true]'

d=$(newdoc specblk); bs --init --doc "$d" >/dev/null; cp "$fx/spec-block.c4" "$repo/docs/specblk.c4"
r=$(bs --doc "$d")
eq "pre-check: specification block in model" "$(jq -c '[.ok, .source, .retryable]' <<<"$r"):$(j '.errors[0].message' "$r" | grep -c 'specification block')" '[false,"model",true]:1'

mkdir -p "$repo/.bf/conventions"
cp "$fx/override-dup.c4" "$repo/.bf/conventions/visualize-spec.c4"
d=$(newdoc dup); bs --init --doc "$d" >/dev/null; cp "$fx/shop.c4" "$repo/docs/dup.c4"
r=$(bs --doc "$d")
eq "pre-check: override redefining a base kind" "$(jq -c '[.ok, .source, .retryable, .final]' <<<"$r")" '[false,"spec",false,true]'
eq "pre-check: override message" "$(j '.errors[0].message' "$r")" "fix your override at $repo/.bf/conventions/visualize-spec.c4: redefines base kind database"
eq "spec fault on call 1: model not stamped, state deleted" "$(head -n 1 "$repo/docs/dup.c4" | grep -cF "$MARKER"):$([ -e "$(bdir dup)/.run-state.json" ] && echo state || echo nostate)" "0:nostate"
rm "$repo/.bf/conventions/visualize-spec.c4"

d=$(newdoc cnt); b=$(bdir cnt); bs --init --doc "$d" >/dev/null; cp "$fx/spec-block.c4" "$repo/docs/cnt.c4"
echo map > "$b/mapping.md"
r1=$(bs --doc "$d"); echo planted > "$b/index.html"; r2=$(bs --doc "$d")
eq "counter: attempts 1,2 not final" "$(j .attempt "$r1"),$(j .final "$r1"),$(j .attempt "$r2"),$(j .final "$r2")" "1,false,2,false"
eq "non-final failures keep mapping.md and index.html" "$([ -e "$b/mapping.md" ] && [ -e "$b/index.html" ] && echo kept || echo lost)" kept
eq "non-final failures do not stamp" "$(j .model_stamped "$r1"),$(j .model_stamped "$r2"):$(head -n 1 "$repo/docs/cnt.c4" | grep -cF "$MARKER")" "false,false:0"
r3=$(bs --doc "$d")
eq "counter: attempt 3 is final" "$(j .attempt "$r3"),$(j .final "$r3")" "3,true"
eq "final failure: stamped first line" "$(j .model_stamped "$r3"):$(head -n 1 "$repo/docs/cnt.c4" | grep -cF "$MARKER")" "true:1"
eq "final failure deletes mapping.md and index.html, and the state file" "$([ -e "$b/mapping.md" ] || [ -e "$b/index.html" ] || [ -e "$b/.run-state.json" ] && echo left || echo gone)" gone
eq "design final failure: no sensitive reminder" "$(j .sensitive_reminder "$r3")" false
eq "counter: 4th call -> not_initialized" "$(err_of bs --doc "$d")" not_initialized:1
bs --init --doc "$d" >/dev/null; bs --doc "$d" >/dev/null; bs --doc "$d" >/dev/null; bs --doc "$d" >/dev/null
eq "stamping is idempotent" "$(grep -cF "$MARKER" "$repo/docs/cnt.c4")" 1

mkdir -p "$repo/docs/architecture" "$repo/.bf/audits"
printf '# audit\n' > "$repo/.bf/audits/arch2-arch-audit.md"
a2=$repo/.bf/audits/arch2-arch-audit.md
bs --init --doc "$a2" >/dev/null; cp "$fx/spec-block.c4" "$repo/docs/architecture/arch2-arch.c4"
r1=$(bs --doc "$a2"); bs --doc "$a2" >/dev/null; r3=$(bs --doc "$a2")
eq "sensitive: false on a non-final failure, true on the final one (model written after init)" "$(j .sensitive_reminder "$r1"),$(j .sensitive_reminder "$r3")" "false,true"
printf '# audit\n' > "$repo/.bf/audits/arch3-arch-audit.md"
a3=$repo/.bf/audits/arch3-arch-audit.md
cp "$fx/spec-block.c4" "$repo/docs/architecture/arch3-arch.c4"; bs --init --doc "$a3" >/dev/null
cp "$fx/override-dup.c4" "$repo/.bf/conventions/visualize-spec.c4"
eq "sensitive: false when the model existed at init" "$(j .sensitive_reminder "$(bs --doc "$a3")")" false
printf '# audit\n' > "$repo/.bf/audits/arch4-arch-audit.md"
a4=$repo/.bf/audits/arch4-arch-audit.md
bs --init --doc "$a4" >/dev/null
eq "sensitive: false when no model was ever written" "$(j .sensitive_reminder "$(bs --doc "$a4")")" false
rm "$repo/.bf/conventions/visualize-spec.c4"

ew=$tmp/elsewhere
mkdir -p "$ew/.bf/audits" "$ew/.bf/conventions" "$ew/docs/architecture"
printf '# audit\n' > "$ew/.bf/audits/x-arch-audit.md"
cp "$fx/override-dup.c4" "$ew/.bf/conventions/visualize-spec.c4"
bs --init --doc "$ew/.bf/audits/x-arch-audit.md" >/dev/null; cp "$fx/shop.c4" "$ew/docs/architecture/x-arch.c4"
eq "outside git: arch-audit doc uses the override at its path-derived root" "$(j .source "$(bs --doc "$ew/.bf/audits/x-arch-audit.md")")" spec

if [ "$online" = true ]; then
  d=$(newdoc ok); b=$(bdir ok); bs --init --doc "$d" >/dev/null; cp "$fx/shop.c4" "$repo/docs/ok.c4"
  r=$(bs --doc "$d")
  eq "case 2: shop.c4 builds clean" "$(jq -c '[.ok, .source, .model_stamped, .warnings, .errors, .views, .element_count, .tbd_count]' <<<"$r")" '[true,null,false,[],[],["index","shop","checkout"],8,1]'
  eq "case 2: html exists" "$([ -s "$(j .html "$r")" ] && echo yes || echo no)" yes
  eq "case 2: html path is the build dir's index.html" "$(j .html "$r")" "$b/index.html"
  eq "case 2: no external script or link" "$(grep -cE '<(script|link)[^>]*(src|href)="(https?:)?//' "$b/index.html")" 0

  d=$(newdoc nested); bs --init --doc "$d" >/dev/null; cp "$fx/nested-actor.c4" "$repo/docs/nested.c4"
  r=$(bs --doc "$d")
  eq "case 3: nested actor is a failure" "$(jq -c '[.ok, .source, .retryable]' <<<"$r"):$(jq -r '.warnings | map(select(contains("nested actors"))) | length' <<<"$r"):$([ -e "$(bdir nested)/index.html" ] && echo html || echo nohtml)" '[false,"model",true]:1:nohtml'

  d=$(newdoc broken); bs --init --doc "$d" >/dev/null; cp "$fx/broken-ref.c4" "$repo/docs/broken.c4"
  r=$(bs --doc "$d")
  eq "broken ref: attributed to the real model path" "$(jq -c '[.ok, .source, .retryable]' <<<"$r"):$(j '.errors[0].file' "$r")" "[false,\"model\",true]:$repo/docs/broken.c4"

  d=$(newdoc badm); bs --init --doc "$d" >/dev/null; cp "$fx/spike/bad-model.c4" "$repo/docs/badm.c4"
  r=$(bs --doc "$d")
  eq "bad-model: dangling ghost ref is attributed to the model" "$(jq -c '[.ok, .source]' <<<"$r"):$(j '.errors[0].file' "$r")" "[false,\"model\"]:$repo/docs/badm.c4"

  cp "$fx/override-ok.c4" "$repo/.bf/conventions/visualize-spec.c4"
  d=$(newdoc ovr); bs --init --doc "$d" >/dev/null; cp "$fx/shop.c4" "$repo/docs/ovr.c4"
  eq "override that adds a kind merges with the base" "$(j .ok "$(bs --doc "$d")")" true
  rm "$repo/.bf/conventions/visualize-spec.c4"

  printf 'specification {\n  element\n}\n' > "$tmp/bad-spec.c4"
  d=$(newdoc badbase); bs --init --doc "$d" >/dev/null; cp "$fx/shop.c4" "$repo/docs/badbase.c4"
  r=$(in_repo env BF_LIKEC4_CACHE_DIR="$cache" BF_VIZ_BASE_SPEC="$tmp/bad-spec.c4" bash "$here/build.sh" --doc "$d")
  eq "base-spec fault: spec, not retryable" "$(jq -c '[.ok, .source, .retryable]' <<<"$r")" '[false,"spec",false]'
  eq "base-spec fault: says plugin bug, never blames the override" "$(jq -r '[.errors[].message] | join(" ")' <<<"$r" | grep -c 'plugin bug, please report'):$(jq -r '[.errors[].message] | join(" ")' <<<"$r" | grep -c 'fix your override')" "1:0"

  d=$(newdoc ftp); b=$(bdir ftp); bs --init --doc "$d" >/dev/null; echo map > "$b/mapping.md"
  cp "$fx/spec-block.c4" "$repo/docs/ftp.c4"; r1=$(bs --doc "$d")
  cp "$fx/shop.c4" "$repo/docs/ftp.c4"; r2=$(bs --doc "$d")
  eq "fail-then-pass: attempt 1 then 2" "$(j .ok "$r1"),$(j .final "$r1"),$(j .ok "$r2"),$(j .attempt "$r2")" "false,false,true,2"
  eq "fail-then-pass: mapping.md and index.html both present" "$([ -e "$b/mapping.md" ] && [ -e "$b/index.html" ] && echo both || echo missing)" both

  d=$(newdoc strip); bs --init --doc "$d" >/dev/null
  { printf '%s\n' "$MARKER"; cat "$fx/shop.c4"; } > "$repo/docs/strip.c4"
  r=$(bs --doc "$d")
  eq "success strips the marker and leaves the rest byte-identical" "$(j .ok "$r"),$(j .model_stamped "$r"):$(cmp -s "$repo/docs/strip.c4" "$fx/shop.c4" && echo same || echo differs)" "true,false:same"

  printf '# audit\n' > "$repo/.bf/audits/arch5-arch-audit.md"
  a5=$repo/.bf/audits/arch5-arch-audit.md
  bs --init --doc "$a5" >/dev/null; cp "$fx/shop.c4" "$repo/docs/architecture/arch5-arch.c4"
  r=$(bs --doc "$a5")
  eq "sensitive: true on a successful first attempt for a new arch-audit model" "$(j .ok "$r"),$(j .final "$r"),$(j .sensitive_reminder "$r")" "true,true,true"
else
  net_skip "build.sh real builds"
fi

gen=$plugin/skills/design/generate/SKILL.md
for h in 'Summary' 'Actors & systems' 'Proposed design'; do
  grep -qF "| $h |" "$gen" || { echo "FAIL producer literal: '| $h |' missing in skills/design/generate/SKILL.md"; fails=$((fails+1)); continue; }
  grep -qF "$h" "$here/viz-paths.sh" || { echo "FAIL producer literal: '$h' missing in viz-paths.sh"; fails=$((fails+1)); continue; }
  echo "PASS producer literal: $h"
done
if grep -qF '$repo-arch-audit.md' "$plugin/skills/arch-audit/scripts/run-state.sh" && grep -qF -e '-arch-audit.md' "$here/viz-paths.sh"; then
  echo "PASS producer literal: -arch-audit.md"
else
  echo "FAIL producer literal: -arch-audit.md differs between skills/arch-audit/scripts/run-state.sh and viz-paths.sh"; fails=$((fails+1))
fi

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
