#!/usr/bin/env bash
# Smoke test for skill-suggest-stop.sh. Each case runs in a fresh directory with its own HOME, log root,
# record root, skills root and TypeSafe stub, so a run never touches the real log or the live API.
#
# Usage: skill-suggest-smoke.sh
# Output: one PASS or FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -uo pipefail

hooks=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook=$hooks/skill-suggest-stop.sh
fixture=$hooks/fixtures/skill-suggest-transcript.jsonl
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
fails=0 ncase=0
out= rc=0

eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

# iso <command...>: runs a command with the state of the current case and nothing of the real machine.
iso() {
  env -u BF_SUGGEST_HOOK -u CLAUDE_PLUGIN_ROOT HOME="$c_home" BF_SUGGEST_LOG_ROOT="$c_log" \
    BF_SUGGEST_RECORD_ROOT="$c_rec" BF_SUGGEST_SKILLS_ROOT="$c_skills" TYPESAFE_ASK="$c_ts" \
    GIT_CEILING_DIRECTORIES="$tmp" "$@"
}

# run <input json> [VAR=value...]: runs the whole hook. Sets out and rc.
run() {
  local input=$1; shift
  rc=0
  out=$(printf '%s' "$input" | iso "$@" bash "$hook" 2>/dev/null) || rc=$?
}

# unit <shell code> [args...]: sources the hook in a subshell and runs the code, with the args as $1 and up.
# The prose-lib EXIT trap forces status 0, so a unit case compares stdout and never the exit code.
unit() {
  local code=$1; shift
  SUGGEST_HOOK=$hook iso bash -c ". \"\$SUGGEST_HOOK\"; $code" unit "$@" 2>/dev/null </dev/null
}

# input [extra json]: a hook input that passes every guard, with the extra keys merged in.
input() {
  local x=${1:-}
  [ -n "$x" ] || x='{}'
  jq -cn --arg tp "${c_tp:-}" --argjson x "$x" \
    '{session_id: "s1", transcript_path: $tp, cwd: "/x", last_assistant_message: "I fixed the build."} + $x'
}

# Transcript line builders. They copy the line shapes of a real session file.
tl_user() { jq -cn --arg t "$1" '{type:"user", message:{role:"user", content:$t}}'; }
tl_cmd() { tl_user "<command-name>/$1</command-name>"; }
tl_meta() { jq -cn '{type:"user", isMeta:true, message:{role:"user", content:[{type:"text", text:"Base directory for this skill: /x"}]}}'; }
tl_result() { jq -cn '{type:"user", message:{role:"user", content:[{type:"tool_result", tool_use_id:"t", content:"ok"}]}}'; }
tl_skill() { jq -cn --arg s "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", id:"t", name:"Skill", input:{skill:$s}}]}}'; }
tl_reply() { jq -cn '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"done"}]}}'; }
tl_pad() { jq -cn --argjson n "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:("x" * $n)}]}}'; }

# scan_state <file> [VAR=value...]: the state that the transcript scan gives for a file.
# capped <file>: the scan of a file with a small tail cap.
capped() { BF_SUGGEST_TAIL_BYTES=800 unit 'suggest_transcript_scan "$1"' "$1"; }
scan_state() { local f=$1; shift; unit 'suggest_transcript_scan "$1"' "$f" | jq -r .state; }

cases_guards() {
  ctx
  run "$(input)"
  eq "a valid input with no tip due prints nothing" "$out" ""
  run "$(input)" BF_SUGGEST_HOOK=off
  eq "off switch prints nothing" "$out|$rc" "|0"
  run 'not json'
  eq "input that is not JSON prints nothing" "$out|$rc" "|0"
  run "$(input '{"session_id":""}')"
  eq "empty session id prints nothing" "$out|$rc" "|0"
  run "$(input '{"agent_id":"a1"}')"
  eq "a sub-agent turn prints nothing" "$out|$rc" "|0"
  run "$(input '{"stop_hook_active":true}')"
  eq "stop_hook_active prints nothing" "$out|$rc" "|0"
  run "$(input '{"last_assistant_message":"── bf:research ──\nDone."}')"
  eq "a reply with a bf banner prints nothing" "$out|$rc" "|0"
  run "$(input '{"last_assistant_message":"── bf:feature | Plan ──"}')"
  eq "a reply with a phase banner prints nothing" "$out|$rc" "|0"
}

cases_registration() {
  local cfg=$hooks/hooks.json
  eq "hooks.json has one Stop command for the hook, timeout 6" \
    "$(jq -r '[.hooks.Stop[].hooks[] | select(.command | test("hooks/skill-suggest-stop[.]sh\"$")) | .timeout] | join(",")' "$cfg")" 6
  eq "hooks.json keeps the prose-stop.sh Stop entry" \
    "$(jq -r '[.hooks.Stop[].hooks[] | select(.command | test("hooks/prose-stop[.]sh"))] | length' "$cfg")" 1
  eq "the registered script exists" "$(test -f "$hook" && echo yes)" yes
}

cases_scan() {
  local f cmd skill
  ctx; f=$c_dir/t.jsonl
  eq "fixture as is: a /clear after the invocation is free" "$(scan_state "$fixture")" free
  eq "fixture as is: the truncated last line does not break the parse" "$(unit 'suggest_transcript_scan "$1"' "$fixture" | jq -r '.state + "|" + .prompt')" "free|"
  head -n 3 "$fixture" > "$f"
  eq "fixture head: a /bf: command in the window is inside" "$(scan_state "$f")" inside
  { tl_cmd bf:research; tl_user a; tl_user b; } > "$f"
  eq "a /bf: command 3rd from the end is inside" "$(scan_state "$f")" inside
  { tl_cmd bf:research; tl_user a; tl_user b; tl_user c; } > "$f"
  eq "the same command 4th from the end is free" "$(scan_state "$f")" free
  { tl_user a; tl_skill bf:feature; tl_user b; } > "$f"
  eq "a bf Skill call in the window is inside" "$(scan_state "$f")" inside
  { tl_skill bf:feature; tl_user a; tl_user b; tl_user c; } > "$f"
  eq "a bf Skill call outside the window is free" "$(scan_state "$f")" free
  { tl_user a; tl_skill other:thing; tl_user b; } > "$f"
  eq "a Skill call of another plugin is free" "$(scan_state "$f")" free
  { tl_cmd bf:research; tl_cmd clear; tl_user a; } > "$f"
  eq "a /clear after the invocation is free" "$(scan_state "$f")" free
  { tl_cmd bf:research; tl_user a; tl_meta; tl_result; tl_meta; tl_result; tl_result; tl_user b; } > "$f"
  eq "isMeta and tool_result entries do not count as prompts" "$(scan_state "$f")" inside
  { tl_cmd bf:research; tl_user a; printf '%s\n' '{"type":"user","message":{"role":"user","content":"cut'; } > "$f"
  eq "a truncated last line does not break the parse" "$(scan_state "$f")" inside
  eq "a missing file is free" "$(scan_state "$c_dir/none.jsonl")" free
  { tl_pad 3000; tl_user a; } > "$f"
  eq "a file over the cap with fewer than 3 prompts in the tail is inside" "$(capped "$f" | jq -r .state)" inside
  { tl_pad 3000; tl_cmd clear; tl_user a; } > "$f"
  eq "a file over the cap with a /clear and fewer than 3 prompts after it is free" "$(capped "$f" | jq -r .state)" free
  { tl_pad 3000; tl_user a; tl_user b; tl_user c; tl_user d; } > "$f"
  eq "a file over the cap with 3 prompts in the tail and no invocation is free" "$(capped "$f" | jq -r .state)" free

  { tl_user first; tl_user "last prompt"; } > "$f"
  eq "prompt of a string content" "$(unit 'suggest_transcript_scan "$1"' "$f" | jq -r .prompt)" "last prompt"
  { tl_user first; jq -cn '{type:"user", message:{role:"user", content:[{type:"text", text:"look"}, {type:"image", source:{}}, {type:"text", text:"here"}]}}'; } > "$f"
  eq "prompt of an array content joins the text items" "$(unit 'suggest_transcript_scan "$1"' "$f" | jq -r .prompt)" $'look\nhere'
  { tl_user "$(head -c 2500 /dev/zero | tr '\0' 'p')"; } > "$f"
  eq "prompt is cut to the prompt limit" "$(unit 'suggest_transcript_scan "$1"' "$f" | jq -r '.prompt | length')" 2000

  { tl_cmd bf:research; tl_user a; } > "$c_dir/tp.jsonl"; c_tp=$c_dir/tp.jsonl
  run "$(input)"
  eq "whole hook run with an inside transcript prints nothing" "$out|$rc" "|0"
}

# mk_skill <name> <description> [suggest value] [extra frontmatter line]: writes a fixture skill into the case skills root.
mk_skill() {
  local d=$c_skills/$1 esc
  mkdir -p "$d"
  esc=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  { printf -- '---\nname: %s\ndescription: "%s"\nmodel: sonnet\n' "$1" "$esc"
    [ -z "${3:-}" ] || printf 'suggest: %s\n' "$3"
    [ -z "${4:-}" ] || printf '%s\n' "$4"
    printf -- '---\n\nBody.\n'; } > "$d/SKILL.md"
}
# cat_field <name> <jq field>: one field of one entry of the catalog of the case skills root.
cat_field() { unit 'suggest_catalog' | jq -r --arg n "$1" "select(.name == \$n) | $2"; }

cases_layout() {
  local self=$hooks/skill-suggest-smoke.sh
  eq "the cases sit in main and main is called on the last line" "$(grep -v '^[[:space:]]*$' "$self" | tail -n 1)" 'main "$@"'
  eq "ctx is defined after main" "$([ "$(grep -n '^ctx()' "$self" | cut -d: -f1)" -gt "$(grep -n '^main()' "$self" | cut -d: -f1)" ] && echo yes)" yes
}

cases_catalog() {
  local research
  ctx
  mk_skill on "Use when the user wants a thing." "" ""
  mk_skill off "Use when internal." false
  mk_skill nokey "Use when the user wants another thing." "" "disable-model-invocation: true"
  mkdir -p "$c_skills/on/phase"; printf -- '---\nname: phase\ndescription: Use when nested.\n---\n' > "$c_skills/on/phase/SKILL.md"
  eq "catalog names" "$(unit 'suggest_catalog' | jq -r .name | sort | tr '\n' ' ')" "nokey on "
  mk_skill quoted 'Use when the user says "fix it" or quotes "x" in a "plan".'
  eq "a description with escaped quotes is read whole" "$(cat_field quoted .description)" 'Use when the user says "fix it" or quotes "x" in a "plan".'
  mk_skill plainq "Use when it is plain text: with a colon."
  eq "an unquoted-looking colon description is kept" "$(cat_field plainq .description)" "Use when it is plain text: with a colon."

  mk_skill r1 "Use when the user wants a plan. Second sentence here."
  eq "reason: Use when becomes Use it when, cut at a period before a capital" "$(cat_field r1 .reason)" "Use it when the user wants a plan."
  mk_skill r2 "Use when the user wants a plan — with a dash."
  eq "reason: cut at an em dash" "$(cat_field r2 .reason)" "Use it when the user wants a plan."
  mk_skill r3 "Use when the user wants a plan; then more."
  eq "reason: cut at a semicolon" "$(cat_field r3 .reason)" "Use it when the user wants a plan."
  mk_skill r4 "Use when the user wants a plan for e.g. the build tool and more words follow here to pass the cut limit"
  eq "reason: a period inside e.g. is not a cut" "$(cat_field r4 '.reason | test("e[.]g[.]")')" "true"
  mk_skill r5 "Use when the user wants a quick walk through every part of a very large and old system today"
  eq "reason: word cut stays within the limit" "$(cat_field r5 '.reason | length <= 81')" "true"
  eq "reason: word cut ends on a whole word" "$(cat_field r5 .reason)" "Use it when the user wants a quick walk through every part of a very large."
  mk_skill r6 "Use when you don't know where to look."
  eq "reason: a contraction empties the reason" "$(cat_field r6 .reason)" ""
  mk_skill r7 "Use when the plugin's docs lag behind."
  eq "reason: a possessive is not a contraction" "$(cat_field r7 .reason)" "Use it when the plugin's docs lag behind."
  mk_skill r8 "Use when the user says 'research X', 'done'. Another sentence follows."
  eq "reason: the opening quote of a trigger phrase is not a contraction" "$(cat_field r8 .reason)" "Use it when the user says 'research X', 'done'."
  mk_skill r9 "Use when the user says 'research X', 'prior art', 'how do other projects solve things', 'compare libraries'."
  eq "reason: a cut inside a quoted phrase goes back to the last closed quote" "$(cat_field r9 .reason)" "Use it when the user says 'research X', 'prior art'."
  mk_skill r9b "Use when the user says 'research the X' or 'how do other projects solve problems of caching' now."
  eq "reason: a cut inside a quoted phrase with no comma goes back before the phrase" "$(cat_field r9b .reason)" "Use it when the user says 'research the X'."
  mk_skill r10 "Quick workflow (refine → research → plan → execute → verify → audit → review → finalize) — skips brainstorm."
  eq "reason: a cut inside a parenthesis goes back before it" "$(cat_field r10 .reason)" "Quick workflow."
  mk_skill r11 'Use when the user says "a long first quoted phrase that runs past the limit of the reason text".'
  eq "reason: nothing is left when the cut removes the only phrase" "$(cat_field r11 .reason)" ""

  research='Use when the user says '"'"'research X'"'"', '"'"'prior art'"'"', '"'"'how do other projects solve…'"'"', '"'"'compare libraries…'"'"', or describes a topic and asks for a research report. Decision-oriented researcher.'
  mk_skill research "$research"
  eq "phrases: the research description gives its quoted phrases" "$(cat_field research '.phrases | join("|")')" "research x|prior art|how do other projects solve…|compare libraries…"
  eq "the real research description gives a reason" "$(cat_field research '.reason | length > 0')" "true"
  mk_skill ph1 "Use when the plugin's docs lag, or (e.g. \"can we make this look nicer\") appears."
  eq "phrases: a possessive gives no phrase and a quote in a parenthesis does" "$(cat_field ph1 '.phrases | join("|")')" "can we make this look nicer"
  mk_skill ph2 "Use when the user says 'don't stop' or 'go on'."
  eq "phrases: an apostrophe inside a phrase does not close it" "$(cat_field ph2 '.phrases | join("|")')" "don't stop|go on"
}

main() {
  cases_layout
  cases_guards
  cases_registration
  cases_scan
  cases_catalog
  [ "$fails" = 0 ]
}

# ctx: a fresh directory and the isolated state of one case. It sets the c_* variables.
ctx() {
  ncase=$((ncase+1))
  c_dir=$tmp/case$ncase
  c_home=$c_dir/home; c_log=$c_dir/log; c_rec=$c_dir/rec; c_skills=$c_dir/skills; c_ts=$c_dir/ts-stub.sh
  c_tp=
  mkdir -p "$c_home" "$c_skills"
  printf '#!/bin/bash\nexit 3\n' > "$c_ts"
}

main "$@"
