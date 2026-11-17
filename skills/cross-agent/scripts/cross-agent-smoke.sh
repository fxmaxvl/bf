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
out=$(bash "$init" < "$tmp/in2")
b2=$(jq -r .bundle_dir <<< "$out")
ok=0
[ "$(jq -r .run <<< "$out")" = null ] || ok=1
[ "$(cat "$b2/args.txt"; printf x)" = $'--lenses logic\n#second linex' ] || ok=1
[ "$b2" != "$bundle" ] || ok=1
check "multi-line args kept without the trailing newline, no run, distinct bundle dir" $ok

err() { bash "$init" <<< "$1" | jq -r .error; }
check "unknown skill" "$([ "$(err 'nosuchskill x')" = unknown_skill ]; echo $?)"
check "unknown runner" "$([ "$(err '--run nope review')" = unknown_runner ]; echo $?)"
check "missing skill" "$([ "$(err '--run codex')" = missing_skill ]; echo $?)"
check "unknown flag" "$([ "$(err '--lenses x bug-hunt')" = unknown_flag ]; echo $?)"
check "self target" "$([ "$(err 'cross-agent review')" = self_target ]; echo $?)"

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

PATH=/usr/bin:/bin bash "$codex_runner" "$bundle" "$tmp/r" 2>/dev/null
check "codex runner exits 127 without codex" "$([ $? = 127 ]; echo $?)"

exit $fail
