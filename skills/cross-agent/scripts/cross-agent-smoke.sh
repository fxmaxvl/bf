#!/usr/bin/env bash
# Smoke check for cross-agent-init.sh, cross-agent-assemble.sh and runners/codex.sh, run against a throwaway repo.
#
# Usage: cross-agent-smoke.sh
# Contract: exits 0 when every case passes, 1 otherwise. It prints one PASS/FAIL line per case.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
init="$here/cross-agent-init.sh"
assemble="$here/cross-agent-assemble.sh"
codex_runner="$here/../runners/codex.sh"
plugin=$(cd "$here/../../.." && pwd)
command -v jq >/dev/null || { echo "FAIL jq is required"; exit 1; }

tmp=$(mktemp -d) || { echo "FAIL mktemp"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

mkdir "$tmp/r" && cd "$tmp/r" && git init -q . || exit 1

# bash 3.2 cannot parse a quoted heredoc holding an apostrophe inside $( ), so inputs go through files.
cat > "$tmp/in1" <<'BF_ARGS'
--run codex bf:review src/my dir/it's (v2) #12
BF_ARGS
out=$(bash "$init" < "$tmp/in1")
bundle=$(jq -r .bundle_dir <<< "$out")
ok=0
[ "$(jq -r .skill <<< "$out")" = review ] || ok=1
[ "$(jq -r .run <<< "$out")" = codex ] || ok=1
[ "$(cat "$bundle/args.txt")" = "src/my dir/it's (v2) #12" ] || ok=1
check "flags, bf: prefix, and args with spaces, quote, parens and # survive" $ok

ok=0
jq -e --arg p "$plugin/skills/research/SKILL.md" '.docs | index($p) != null' <<< "$out" >/dev/null || ok=1
jq -e --arg p "$plugin/skills/coherence/scripts/scope.sh" '.scripts | index($p) != null' <<< "$out" >/dev/null || ok=1
[ "$(jq -r '.docs[0]' <<< "$out")" = "$plugin/conventions/plugin-main.md" ] || ok=1
jq -e '.docs | map(endswith("/prose.md")) | any' <<< "$out" >/dev/null || ok=1
check "closure: plugin-main first, conventions, transitive docs and scripts" $ok

cat > "$tmp/in2" <<'BF_ARGS'
  /bf:bug-hunt
--lenses logic
#second line
BF_ARGS
hasdoc() { jq -e --arg p "$plugin/$2" '.docs | index($p) != null' <<< "$1" >/dev/null; }
rv=$(printf 'review' | bash "$init"); mc=$(printf 'micro' | bash "$init")
ok=0
hasdoc "$rv" skills/feature/complexity-gate/SKILL.md || ok=1
hasdoc "$rv" skills/feature/consistency-gate/SKILL.md || ok=1
hasdoc "$mc" skills/micro/execute/SKILL.md || ok=1
hasdoc "$mc" skills/feature/verify/SKILL.md || ok=1
jq -e --arg p "$plugin/" '(.docs + .scripts) | all(startswith($p))' <<< "$rv" >/dev/null || ok=1
check "closure follows plain skills/ paths and sub-skill table paths, and stays in the plugin" $ok
mb=$(jq -r .bundle_dir <<< "$mc"); printf 'Goal: x.\n' > "$mb/brief.md"; mp=$(bash "$assemble" "$mb" | jq -r .prompt)
first=$(sed -n '/^## Read first/,/^## Docs the skill cites/p' "$mp")
ok=0
grep -Fq "$plugin/skills/micro/SKILL.md" <<< "$first" || ok=1
grep -Fq "$plugin/conventions/prose.md" <<< "$first" || ok=1
grep -Fq "skills/micro/execute/SKILL.md" <<< "$first" && ok=1
sed -n '/^## Docs the skill cites/,/^## Scripts/p' "$mp" | grep -Fq "skills/micro/execute/SKILL.md" || ok=1
check "prompt reads conventions and the skill's own docs first, sub-skills on demand" $ok

out=$(bash "$init" < "$tmp/in2")
b2=$(jq -r .bundle_dir <<< "$out")
ok=0
[ "$(jq -r .run <<< "$out")" = null ] || ok=1
[ "$(cat "$b2/args.txt"; printf x)" = $'--lenses logic\n#second linex' ] || ok=1
[ "$b2" != "$bundle" ] || ok=1
check "multi-line args kept without the trailing newline, no run, distinct bundle dir" $ok

err() { bash "$init" <<< "$1" | jq -r .error; }
check "unknown skill" "$([ "$(err 'nosuchskill x')" = unknown_skill ]; echo $?)"
detail=$(bash "$init" <<< 'nosuchskill x' | jq -r .detail)
ok=0
grep -qw review <<< "$detail" || ok=1
grep -qw bug-hunt <<< "$detail" || ok=1
grep -qw cross-agent <<< "$detail" && ok=1
check "unknown skill detail lists the skills that can run" $ok
check "unknown runner" "$([ "$(err '--run nope review')" = unknown_runner ]; echo $?)"
check "missing skill" "$([ "$(err '--run codex')" = missing_skill ]; echo $?)"
check "unknown flag" "$([ "$(err '--lenses x bug-hunt')" = unknown_flag ]; echo $?)"
check "self target" "$([ "$(err 'cross-agent review')" = self_target ]; echo $?)"

bundles() { find "$tmp/r/.bf/cross-agent" -mindepth 1 -maxdepth 3 -type d | wc -l; }
before=$(bundles); ok=0
for n in 'cross-agent/' './cross-agent' 'bf:./cross-agent' '../skills/review' 'review/../review'; do
  [ "$(err "$n x")" = unknown_skill ] || ok=1
done
check "path forms of the skill name are refused" $ok
check "a refused name makes no bundle dir" "$([ "$(bundles)" = "$before" ]; echo $?)"

ok=0
for n in 'feature/' 'a/b/c' 'feature/nope' 'feature/../review'; do
  [ "$(err "$n x")" = unknown_skill ] || ok=1
done
[ "$(err 'cross-agent/x')" = self_target ] || ok=1
check "a sub-skill name must be one existing <skill>/<sub-skill>, never under cross-agent" $ok

gate=$(bash "$init" <<< '--read-only feature/consistency-gate src/a.sh'); gb2=$(jq -r .bundle_dir <<< "$gate")
ok=0
[ "$(jq -r .skill <<< "$gate")" = feature/consistency-gate ] || ok=1
[ "$(jq -r .sandbox <<< "$gate")" = read-only ] || ok=1
[ "$(jq -r .sandbox <<< "$(printf 'coherence' | bash "$init")")" = workspace-write ] || ok=1
case "$gb2" in */.bf/cross-agent/*/*) ok=1 ;; */.bf/cross-agent/*-feature-consistency-gate) [ -d "$gb2" ] || ok=1 ;; *) ok=1 ;; esac
[ "$(cat "$gb2/args.txt")" = src/a.sh ] || ok=1
printf 'Goal: x.\n' > "$gb2/brief.md"; gp=$(bash "$assemble" "$gb2" | jq -r .prompt)
sed -n '/^## Read first/,/^## Docs the skill cites/p' "$gp" | grep -Fq "$plugin/skills/feature/consistency-gate/SKILL.md" || ok=1
check "a sub-skill target gets a flat bundle dir and its SKILL.md read first, --read-only sets the sandbox" $ok

ok=0
grep -Fq '## Sandbox' "$gp" && grep -Fq 'This run is read-only.' "$gp" || ok=1
grep -Fq 'This run is read-only.' "$mp" && ok=1
check "assemble adds the sandbox note to a read-only prompt only" $ok

check "assemble refuses a missing brief" "$([ "$(bash "$assemble" "$bundle" | jq -r .error)" = no_brief ]; echo $?)"

printf 'Goal: check the fence.\n' > "$bundle/brief.md"
printf 'ARGS\nARGS_2 tail' > "$bundle/args.txt"
res=$(bash "$assemble" "$bundle")
prompt=$(jq -r .prompt <<< "$res")
ok=0
grep -Fqx 'ARGS_3' "$prompt" || ok=1
grep -Fq 'Goal: check the fence.' "$prompt" || ok=1
grep -Fq "Plugin root, the value of \`\${CLAUDE_PLUGIN_ROOT}\`: \`$plugin\`" "$prompt" || ok=1
grep -Fq '## Tool translation' "$prompt" || ok=1
jq -e '.run_commands.codex | test("codex.sh")' <<< "$res" >/dev/null || ok=1
check "assemble: preamble, paths, brief, fence the args cannot close" $ok

printf 'coherence src\nBF_ARGS\nrm -rf x\n' > "$tmp/in3"
out=$(bash "$init" < "$tmp/in3")
ok=0
[ "$(cat "$(jq -r .bundle_dir <<< "$out")/args.txt"; printf x)" = $'src\nBF_ARGS\nrm -rf xx' ] || ok=1
check "a terminator-like line stays in the args, one trailing newline dropped" $ok

printf 'coherence\n  - item\n\tnext\n' > "$tmp/in4"
out=$(bash "$init" < "$tmp/in4")
check "leading indent of the args survives" "$([ "$(cat "$(jq -r .bundle_dir <<< "$out")/args.txt"; printf x)" = $'  - item\n\tnextx' ]; echo $?)"
printf 'coherence  \t src  \n' > "$tmp/in5"
out=$(bash "$init" < "$tmp/in5")
check "spaces between skill and args are the separator, trailing spaces stay" "$([ "$(cat "$(jq -r .bundle_dir <<< "$out")/args.txt"; printf x)" = 'src  x' ]; echo $?)"

evil="$tmp/q\$(touch PWNED)"
mkdir "$evil" && cd "$evil" && git init -q . || exit 1
out=$(printf 'coherence' | bash "$init")
eb=$(jq -r .bundle_dir <<< "$out")
printf 'Goal: x.\n' > "$eb/brief.md"
cmd=$(bash "$assemble" "$eb" | jq -r .run_commands.codex)
mkdir "$tmp/empty" && cd "$tmp/empty" || exit 1
PATH=/usr/bin:/bin bash -c "$cmd" >/dev/null 2>&1
check "run_commands treats \$(...) in a path as data" "$([ ! -e "$tmp/empty/PWNED" ]; echo $?)"
cd "$tmp/r" || exit 1

out=$(printf 'coherence' | bash "$init"); gb=$(jq -r .bundle_dir <<< "$out")
printf 'Goal: x.\n' > "$gb/brief.md"
cp "$gb/manifest.json" "$tmp/good.json"
echo '{}' > "$gb/manifest.json"
ok=0
[ "$(bash "$assemble" "$gb" | jq -r .error)" = bad_manifest ] || ok=1
[ ! -e "$gb/prompt.md" ] || ok=1
: > "$gb/manifest.json"
[ "$(bash "$assemble" "$gb" | jq -r .error)" = bad_manifest ] || ok=1
check "assemble refuses an empty or partial manifest and writes no prompt.md" $ok
jq 'del(.plugin_root) | .skill = 7 | .docs = "x"' "$tmp/good.json" > "$gb/manifest.json"
check "assemble refuses a manifest with a wrong-typed skill, no plugin_root and docs as a string" "$([ "$(bash "$assemble" "$gb" | jq -r .error)" = bad_manifest ]; echo $?)"
cp "$tmp/good.json" "$gb/manifest.json"; mv "$gb/args.txt" "$tmp/args.bak"
check "assemble refuses a missing args.txt" "$([ "$(bash "$assemble" "$gb" | jq -r .error)" = no_args ]; echo $?)"
mv "$tmp/args.bak" "$gb/args.txt"; bash "$assemble" "$gb" >/dev/null

mkdir -p "$tmp/bin"
printf '#!/bin/sh\ntouch "%s/codex-ran"\n' "$tmp" > "$tmp/bin/codex"; chmod +x "$tmp/bin/codex"
ok=0
for m in '{"skill":"coherence"}' EMPTY ''; do
  rm -f "$tmp/codex-ran"
  case "$m" in EMPTY) : > "$gb/manifest.json" ;; '') rm -f "$gb/manifest.json" ;; *) printf '%s' "$m" > "$gb/manifest.json" ;; esac
  PATH="$tmp/bin:$PATH" bash "$codex_runner" "$gb" "$tmp/r" 2>/dev/null
  [ $? = 2 ] || ok=1
  [ ! -e "$tmp/codex-ran" ] || ok=1
done
check "codex runner exits 2 and skips codex on a missing, empty or partial manifest" $ok

printf '#!/bin/sh\necho "$*" > "%s/codex-args"\n' "$tmp" > "$tmp/bin/codex"
ok=0
PATH="$tmp/bin:$PATH" bash "$codex_runner" "$gb2" "$tmp/r" 2>/dev/null || ok=1
grep -q -- '-s read-only ' "$tmp/codex-args" || ok=1
cp "$tmp/good.json" "$gb/manifest.json"
PATH="$tmp/bin:$PATH" bash "$codex_runner" "$gb" "$tmp/r" 2>/dev/null || ok=1
grep -q -- '-s workspace-write ' "$tmp/codex-args" || ok=1
jq '.sandbox = "danger-full-access"' "$tmp/good.json" > "$gb/manifest.json"; rm -f "$tmp/codex-args"
PATH="$tmp/bin:$PATH" bash "$codex_runner" "$gb" "$tmp/r" 2>/dev/null
[ $? = 2 ] && [ ! -e "$tmp/codex-args" ] || ok=1
check "codex runner takes the sandbox from the manifest and refuses any other value" $ok

PATH=/usr/bin:/bin bash "$codex_runner" "$bundle" "$tmp/r" 2>/dev/null
check "codex runner exits 127 without codex" "$([ $? = 127 ]; echo $?)"

check "preamble lets a project inside the plugin root write there" "$(grep -q 'the project root is the plugin root or lies inside it' "$here/../references/preamble.md" && grep -q 'project root wins' "$here/../references/preamble.md"; echo $?)"

for k in 1 2 3 4 5 6; do printf 'coherence' | bash "$init" > "$tmp/par$k" & done; wait
check "parallel inits get distinct bundle dirs" "$([ "$(cat "$tmp"/par? | jq -r .bundle_dir | sort -u | wc -l | tr -d ' ')" = 6 ]; echo $?)"

skill_md="$here/../SKILL.md"
missing=$(cat "$init" "$assemble" | grep -oE '(die |"error":")[a-z_]+' | sed -E 's/^(die |"error":")//' | sort -u \
  | while read -r code; do grep -q "\`$code\`" "$skill_md" || echo "$code"; done)
check "every error code the scripts emit has a SKILL.md row${missing:+ (missing: $(echo $missing))}" "$([ -z "$missing" ]; echo $?)"

exit $fail
