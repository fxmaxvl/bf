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
tmp=$(mktemp -d) && [ -n "$tmp" ] && tmp=$(cd "$tmp" && pwd -P) || { echo "ABORT: cannot create a temp directory" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT
fails=0 ncase=0
out= rc=0

eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

# iso <command...>: runs a command with the state of the current case and nothing of the real machine.
iso() {
  env -u BF_SUGGEST_HOOK -u CLAUDE_PLUGIN_ROOT HOME="$c_home" BF_SUGGEST_LOG_ROOT="$c_log" \
    BF_PROSE_RECORD_ROOT="$c_rec" BF_SUGGEST_SKILLS_ROOT="$c_skills" TYPESAFE_ASK="$c_ts" \
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
  jq -cn --arg tp "${c_tp:-}" --arg cwd "$tmp" --argjson x "$x" \
    '{session_id: "s1", transcript_path: $tp, cwd: $cwd, last_assistant_message: "I fixed the build."} + $x'
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
  eq "hooks.json has one Stop command for the hook, timeout 8" \
    "$(jq -r '[.hooks.Stop[].hooks[] | select(.command | test("hooks/skill-suggest-stop[.]sh\"$")) | .timeout] | join(",")' "$cfg")" 8
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

# stub <rc> <stdout text> [sleep seconds]: makes the TypeSafe stub of the case. It records that it ran and the
# files it was given, then prints the text and exits with the code.
stub() {
  {
    echo '#!/bin/bash'
    echo "d=$c_dir"
    cat <<'EOS'
touch "$d/called"
while [ $# -gt 0 ]; do
  case "$1" in
    --questions) cp "$2" "$d/q.json"; shift 2 ;;
    --state) cp "$2" "$d/s.json"; shift 2 ;;
    *) shift ;;
  esac
done
echo "noise on stderr" >&2
EOS
    [ -z "${3:-}" ] || printf 'sleep %s\n' "$3"
    printf 'printf %%s %q\n' "$2"
    printf 'exit %s\n' "$1"
  } > "$c_ts"
}
# answer <noul> <choice> <confidence>: the answers JSON of TypeSafe for the two questions of the hook.
answer() {
  jq -cn --argjson n "$1" --arg c "$2" --argjson f "$3" \
    '{helps: {type: "noul", noul: $n}, skill: {type: "choice", choice: $c, confidence: $f, probabilities: {}}}'
}
called() { test -f "$c_dir/called" && echo yes || echo no; }
# fixture_skills: three candidates and one skill that opts out.
fixture_skills() {
  mk_skill alpha "Use when the user wants alpha work. Say 'alpha one' or 'alpha two'."
  mk_skill beta "Use when the user wants beta work. Say 'beta one' or 'beta two'."
  mk_skill meta "Use when the user says 'a.c' or 'x(y)?'."
  mk_skill hidden "Use when internal. Say 'hidden one' or 'hidden two'." false
}
# tip_text <out>: the tip sentence of a hook output.
tip_text() { printf '%s' "$1" | jq -r '.systemMessage // empty' 2>/dev/null; }

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
  mk_skill r4 "Use when the user wants a plan for e.g. the build tool, and more words follow here to pass the cut limit"
  eq "reason: a period inside e.g. is not a cut" "$(cat_field r4 '.reason | test("e[.]g[.]")')" "true"
  mk_skill r5 "Use when the user wants a quick walk through every part of a very large and old system today"
  eq "reason: a clause over the limit with no comma gives an empty reason" "$(cat_field r5 .reason)" ""
  mk_skill r6 "Use when you don't know where to look."
  eq "reason: the catalog leaves the prose rules to the lint, so a contraction stays" "$(cat_field r6 .reason)" "Use it when you don't know where to look."
  mk_skill r7 "Use when the plugin's docs lag behind."
  eq "reason: a possessive is not a contraction" "$(cat_field r7 .reason)" "Use it when the plugin's docs lag behind."
  mk_skill r8 "Use when the user says 'research X', 'done'. Another sentence follows."
  eq "reason: the opening quote of a trigger phrase is not a contraction" "$(cat_field r8 .reason)" "Use it when the user says 'research X', 'done'."
  mk_skill r9 "Use when the user says 'research X', 'prior art', 'how do other projects solve things', 'compare libraries'."
  eq "reason: a cut inside a quoted phrase goes back to the last closed quote" "$(cat_field r9 .reason)" "Use it when the user says 'research X', 'prior art'."
  mk_skill r9b "Use when the user says 'research the X' or 'how do other projects solve problems of caching' now."
  eq "reason: a cut inside a quoted phrase with no comma gives an empty reason" "$(cat_field r9b .reason)" ""
  mk_skill r9c "Use when the user says 'research X', 'how do other projects solve problems, of caching' now."
  eq "reason: a comma cut inside a quoted phrase gives an empty reason" "$(cat_field r9c .reason)" ""
  mk_skill r10 "Quick workflow (refine → research → plan → execute → verify → audit → review → finalize) — skips brainstorm."
  eq "reason: a parenthesis that the clause limit cuts gives an empty reason" "$(cat_field r10 .reason)" ""
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

cases_ask() {
  local text long
  ctx; fixture_skills
  stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input)"
  eq "a confident pick prints a tip with the reason" "$(tip_text "$out")" "Tip: /bf:alpha fits this. Use it when the user wants alpha work."
  eq "the tip object has exactly one key" "$(printf '%s' "$out" | jq -c 'keys')" '["systemMessage"]'
  eq "noise of the stub does not reach stdout" "$(printf '%s' "$out" | jq -c 'type')" '"object"'
  eq "the questions hold every candidate and none, and not the opt-out skill" "$(jq -r '.skill.criteria | keys | join(",")' "$c_dir/q.json")" "alpha,beta,meta,none"
  eq "the helps question is a noul" "$(jq -r '.helps.type' "$c_dir/q.json")" noul
  rm -f "$c_dir/called"
  eq "twin of the guards: the same input with a sub-agent id asks nothing" "$(run "$(input '{"agent_id":"a"}')"; echo "$out|$(called)")" "|no"
  run "$(input '{"stop_hook_active":true}')"; eq "twin: stop_hook_active asks nothing" "$out|$(called)" "|no"
  run "$(input '{"last_assistant_message":"── bf:feature | Plan ──"}')"; eq "twin: a banner asks nothing" "$out|$(called)" "|no"
  run "$(input)" BF_SUGGEST_HOOK=off; eq "twin: the off switch asks nothing" "$out|$(called)" "|no"
  { tl_cmd bf:research; tl_user a; } > "$c_dir/inside.jsonl"; c_tp=$c_dir/inside.jsonl
  run "$(input)"; eq "twin: an inside transcript asks nothing" "$out|$(called)" "|no"
  c_tp=

  stub 0 "$(answer 0.9 alpha 0.79)"; run "$(input)"; eq "confidence below the bar prints nothing" "$out" ""
  stub 0 "$(answer 0.5 alpha 0.95)"; run "$(input)"; eq "helps below the bar prints nothing" "$out" ""
  stub 0 "$(answer 0.9 none 0.95)"; run "$(input)"; eq "choice none prints nothing" "$out" ""
  stub 0 "$(answer 0.9 hidden 0.95)"; run "$(input)"; eq "a choice outside the catalog prints nothing" "$out" ""
  stub 0 ""; run "$(input)"; eq "exit 0 with empty stdout prints nothing" "$out" ""
  stub 0 "not json"; run "$(input)"; eq "exit 0 with text that is not JSON prints nothing" "$out" ""
  stub 0 "{}"; run "$(input)"; eq "exit 0 with an answer that lacks helps and skill prints nothing" "$out" ""
  stub 2 ""; run "$(input)"; eq "exit 2 prints nothing" "$out" ""
  run "$(input)" TYPESAFE_ASK="$c_dir/missing.sh"; eq "a missing script prints nothing" "$out" ""

  long=$(head -c 5000 /dev/zero | tr '\0' 'r')
  { tl_user "$(head -c 2500 /dev/zero | tr '\0' 'p')"; } > "$c_dir/long.jsonl"; c_tp=$c_dir/long.jsonl
  stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input "$(jq -cn --arg m "$long" '{last_assistant_message: $m}')")"
  eq "the state holds the last reply characters up to the reply limit" "$(jq -r '.reply | length' "$c_dir/s.json")" 4000
  eq "the state holds the prompt up to the prompt limit" "$(jq -r '.user_prompt | length' "$c_dir/s.json")" 2000
  c_tp=
}

cases_fallback() {
  ctx; fixture_skills
  local cat
  cat=$(unit 'suggest_catalog')
  fb() { unit 'suggest_fallback "$1" "$2" "$3"' "$cat" "$1" "$2"; }
  eq "two distinct phrases of one skill pick it" "$(fb "please do alpha one" "and also alpha two")" alpha
  eq "one phrase picks nothing" "$(fb "alpha one" "nothing else")" ""
  eq "the same phrase twice counts once" "$(fb "alpha one alpha one" "alpha one")" ""
  eq "a tie at the minimum picks nothing" "$(fb "alpha one alpha two" "beta one beta two")" ""
  eq "a higher score beats a lower one" "$(fb "alpha one alpha two beta one" "")" alpha
  eq "the match ignores case" "$(fb "ALPHA One" "alpha TWO")" alpha
  eq "a phrase with regex characters matches as plain text" "$(fb "see a.c and x(y)? here" "")" meta
  eq "a regex character does not act as a pattern" "$(fb "see abc and xyy here" "")" ""

  stub 3 ""
  run "$(input '{"last_assistant_message":"We could try alpha one, then alpha two."}')"
  eq "exit 3 with a strong match prints the fallback tip" "$(tip_text "$out")" "Tip: /bf:alpha fits this. Use it when the user wants alpha work."
  run "$(input '{"last_assistant_message":"We could try alpha one only."}')"
  eq "exit 3 with a weak match prints nothing" "$out" ""
  stub 0 "$(answer 0.9 none 0.95)"
  run "$(input '{"last_assistant_message":"We could try alpha one, then alpha two."}')"
  eq "an answer of none never runs the fallback" "$out" ""
  stub 0 "not json"
  run "$(input '{"last_assistant_message":"We could try alpha one, then alpha two."}')"
  eq "a malformed answer never runs the fallback" "$out" ""

  # The bound is one second under the hooks.json limit, so a loaded machine still ends in time.
  local ask_timeout limit bound t0 t1
  ask_timeout=$(unit 'printf %s "$SUGGEST_ASK_TIMEOUT"')
  limit=$(jq -r '[.hooks.Stop[].hooks[] | select(.command | test("hooks/skill-suggest-stop[.]sh\"$")) | .timeout][0]' "$hooks/hooks.json")
  bound=$((limit - 1))
  stub 3 "" "$ask_timeout"
  t0=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time')
  run "$(input '{"session_id":"slow","last_assistant_message":"We could try alpha one, then alpha two."}')"
  t1=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time')
  eq "a slow TypeSafe call ends with the fallback tip in under $bound seconds" "$(awk -v a="$t0" -v b="$t1" -v m="$bound" 'BEGIN { exit !(b - a < m) }' && tip_text "$out")" "Tip: /bf:alpha fits this. Use it when the user wants alpha work."
}

cases_unavailable() {
  local msg
  ctx; fixture_skills
  msg='{"last_assistant_message":"We could try alpha one, then alpha two."}'
  stub 3 ""
  run "$(input "$msg")" TMPDIR=$c_dir/no-such-dir BF_PROSE_RECORD_ROOT=$c_rec
  eq "no temp file is a hook fault: no fallback tip, no call" "$out|$(called)" "|no"
  run "$(input "$msg")"
  eq "twin: with a temp directory the same input gives the fallback tip" "$(tip_text "$out" | cut -c1-24)|$(called)" "Tip: /bf:alpha fits this|yes"
  rm -f "$c_dir/called"
  eq "questions that are not JSON are a hook fault: silent, no call" \
    "$(unit 'suggest_build_questions() { echo "{bad"; }; suggest_ask "$1" p r' "$(unit suggest_catalog)")|$(called)" "silent|no"
  eq "twin: good questions reach the script and exit 3 means fallback" "$(unit 'suggest_ask "$1" p r' "$(unit suggest_catalog)")|$(called)" "fallback|yes"
}

cases_tip() {
  local lint t
  ctx
  eq "tip with a reason" "$(unit 'suggest_tip "$1"' '{"skill":"research","reason":"Use it when the user says '"'"'research X'"'"'."}' | jq -r .systemMessage)" "Tip: /bf:research fits this. Use it when the user says 'research X'."
  eq "tip drops a reason that the prose lint rejects" "$(unit 'suggest_tip "$1"' '{"skill":"quick","reason":"Use it when you don'"'"'t know."}' | jq -r .systemMessage)" "Tip: /bf:quick fits this."
  eq "tip with an empty reason" "$(unit 'suggest_tip "$1"' '{"skill":"quick","reason":""}' | jq -r .systemMessage)" "Tip: /bf:quick fits this."
  fixture_skills; stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input)"
  t=$(tip_text "$out")
  printf '%s' "$t" | bash "$hooks/../skills/plain/scripts/prose-lint.sh" - --mode chat --format json >/dev/null 2>&1; lint=$?
  eq "the tip text has no hard marker of the prose lint" "$lint" 0
}


cases_dedupe() {
  local uid recdir
  uid=$(id -u)
  ctx; fixture_skills
  recdir=$c_rec/bf-suggest-$uid
  stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input)"; eq "dedupe: the first tip prints" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
  run "$(input)"; eq "dedupe: the same skill in the same session prints nothing" "$out" ""
  stub 0 "$(answer 0.9 beta 0.9)"
  run "$(input)"; eq "dedupe: another skill in the same session still prints" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:beta fits t"
  stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input '{"session_id":"s2"}')"; eq "dedupe: another session prints again" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
  eq "dedupe: the record dir mode is 700" "$(ls -ld "$recdir" | cut -c1-10)" "drwx------"

  ctx; fixture_skills; stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input)" BF_PROSE_UID=99999; eq "a foreign owner still prints the tip" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
  run "$(input)" BF_PROSE_UID=99999; eq "a foreign owner prints it again, so nothing was recorded" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
  eq "a foreign owner writes no record file" "$(find "$c_rec" -type f | wc -l | tr -d ' ')" 0

  ctx; fixture_skills; stub 0 "$(answer 0.9 alpha 0.9)"
  mkdir -p "$c_rec" "$c_dir/target"; ln -s "$c_dir/target" "$c_rec/bf-suggest-$uid"
  run "$(input)"; eq "a symlinked record dir still prints the tip" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
  eq "a symlinked record dir is not written through" "$(find "$c_dir/target" -type f | wc -l | tr -d ' ')" 0

  ctx; fixture_skills; stub 0 "$(answer 0.9 alpha 0.9)"
  mkdir -p -m 700 "$c_rec/bf-suggest-$uid"; printf 'keep\n' > "$c_dir/victim"; ln -s "$c_dir/victim" "$c_rec/bf-suggest-$uid/s1"
  run "$(input)"; eq "a symlinked record file still prints the tip" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
  eq "a symlinked record file is not written through" "$(cat "$c_dir/victim")" keep
}

cases_log() {
  local reply
  ctx
  reply="Caching caching cache layer layer redis 2024 the and with because database database database tuning tuning alpha1 bravo2 charlie3 delta4 echoes"
  eq "reply_words ranks by count then first position, with no short word, number or common word" \
    "$(unit 'suggest_words "$1"' "$reply" | jq -r 'join(" ")')" "database caching layer tuning cache redis alpha1 bravo2"
  eq "reply_words keeps at most the top words" "$(unit 'suggest_words "$1"' "$reply" | jq 'length')" 8

  ctx; fixture_skills
  local log=$c_log/log.jsonl rep="We could try the caching layer redesign because queries run slowly under production traffic again"
  stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input "$(jq -cn --arg m "$rep" '{last_assistant_message: $m}')")"
  eq "a shown tip writes one line: typesafe, a number, shown true" "$(jq -c '[.skill, .source, .confidence, .shown]' "$log")" '["alpha","typesafe",0.9,true]'
  eq "the log line holds the repo name and a UTC time" "$(jq -r '(.repo | length > 0) and (.time | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$log")" true
  eq "the log line holds no 5-word run of the reply" "$(echo "$rep" | tr ' ' '\n' | awk '{w[NR]=$0} END{for(i=1;i+4<=NR;i++) print w[i]" "w[i+1]" "w[i+2]" "w[i+3]" "w[i+4]}' | while read -r run5; do grep -qF "$run5" "$log" && echo hit; done | wc -l | tr -d ' ')" 0
  run "$(input)"
  eq "a dedupe hit writes shown false and keeps the skill" "$(tail -n 1 "$log" | jq -c '[.skill, .shown]')" '["alpha",false]'
  stub 0 "$(answer 0.9 none 0.95)"; run "$(input '{"session_id":"s9"}')"
  eq "a pick of none writes skill none and shown false" "$(tail -n 1 "$log" | jq -c '[.skill, .shown]')" '["none",false]'
  stub 0 "$(answer 0.4 beta 0.9)"; run "$(input '{"session_id":"s9"}')"
  eq "helps below the bar with a candidate choice writes that skill, shown false" "$(tail -n 1 "$log" | jq -c '[.skill, .confidence, .shown]')" '["beta",0.9,false]'
  stub 0 "$(answer 0.9 beta 0.79)"; run "$(input '{"session_id":"s9"}')"
  eq "a candidate choice below the confidence bar writes that skill, shown false" "$(tail -n 1 "$log" | jq -c '[.skill, .confidence, .shown]')" '["beta",0.79,false]'
  stub 0 "$(answer 0.9 hidden 0.9)"; run "$(input '{"session_id":"s9"}')"
  eq "a choice outside the catalog writes none" "$(tail -n 1 "$log" | jq -r '.skill')" none
  stub 3 ""; run "$(input '{"session_id":"s10","last_assistant_message":"try alpha one and alpha two"}')"
  eq "a fallback run writes source keyword and a null confidence" "$(tail -n 1 "$log" | jq -c '[.skill, .source, .confidence, .shown]')" '["alpha","keyword",null,true]'

  ctx; fixture_skills; log=$c_log/log.jsonl
  stub 2 ""; run "$(input)"; eq "an exit 2 stub writes no line" "$(test -e "$log" && echo yes || echo no)" no
  stub 0 ""; run "$(input)"; eq "an exit 0 stub with empty stdout writes no line" "$(test -e "$log" && echo yes || echo no)" no
  stub 0 "not json"; run "$(input)"; eq "a malformed answer writes no line" "$(test -e "$log" && echo yes || echo no)" no
  stub 0 "$(answer 0.9 alpha 0.9)"; run "$(input)" BF_SUGGEST_HOOK=off; eq "a guard exit writes no line" "$(test -e "$log" && echo yes || echo no)" no
  run "$(input '{"agent_id":"a"}')"; eq "a sub-agent turn writes no line" "$(test -e "$log" && echo yes || echo no)" no
  run "$(input)"; eq "twin: the same input without the guard writes a line" "$(wc -l < "$log" | tr -d ' ')" 1

  ctx; fixture_skills; log=$c_log/log.jsonl
  mkdir -p "$c_log"; head -c 300 /dev/zero | tr '\0' 'z' > "$log"
  stub 0 "$(answer 0.9 alpha 0.9)"; run "$(input)" BF_SUGGEST_LOG_MAX_BYTES=100
  eq "a log over the size limit moves to log.jsonl.1" "$(wc -c < "$log.1" | tr -d ' ')" 300
  eq "the new log has one line" "$(wc -l < "$log" | tr -d ' ')" 1

  ctx; fixture_skills; stub 0 "$(answer 0.9 alpha 0.9)"
  run "$(input)" BF_SUGGEST_LOG_ROOT=/dev/null/nope
  eq "a log root that cannot be written still gives the tip" "$(tip_text "$out" | cut -c1-20)" "Tip: /bf:alpha fits "
}

# clean_end <description> <reason>: prints true when the reason is empty, or is the start of the description
# and stops at a clause boundary of it: a comma, a semicolon, an em dash, a sentence end, or the end.
clean_end() {
  jq -nr --arg d "$1" --arg r "$2" '
    ($d | sub("^Use when"; "Use it when")) as $d
    | ($r | sub("[.]$"; "")) as $r
    | $r == "" or ($d | startswith($r) and (.[($r | length):] | test("^($|,|;| —|[.] [A-Z]|[.]$)")))'
}

cases_real_skills() {
  local f prefix cat bad r q n
  ctx; c_skills=$hooks/../skills
  cat=$(unit 'suggest_catalog')
  eq "the real catalog has 29 candidates" "$(printf '%s\n' "$cat" | jq -s 'length')" 29
  eq "the real catalog has none of the 9 opt-out skills" "$(printf '%s\n' "$cat" | jq -rs '[.[].name | select(. == "self-audit" or . == "self-heal" or . == "write-skill" or . == "onboard-skill" or . == "typesafe" or . == "setup" or . == "kit" or . == "cross-agent" or . == "autopilot")] | length')" 0
  eq "the real catalog gives at least 12 skills with 2 or more trigger phrases" "$(printf '%s\n' "$cat" | jq -s '[.[] | select(.phrases | length >= 2)] | length >= 12')" true

  prefix=$(unit 'printf %s "$SUGGEST_BANNER_PREFIX"')
  bad=0
  for f in "$hooks"/../skills/*/SKILL.md; do
    n=$(basename "$(dirname "$f")")
    [ "$(printf '%s\n' "$cat" | jq -r --arg n "$n" 'select(.name == $n) | .name')" = "$n" ] || continue
    grep -qF -- "$prefix" "$f" || { echo "FAIL banner prefix missing in $f"; bad=$((bad+1)); }
    # A banner line starts with ── and may sit in backticks. Each one must be ── bf:<name> or ── bf:<name> | <Phase>.
    while IFS= read -r l; do
      printf '%s\n' "$l" | grep -Eq -- "── bf:$n( \\| .+)? ─" || { echo "FAIL banner form in $f: $l"; bad=$((bad+1)); }
    done < <(grep -F -- '── ' "$f" | grep -E -- '(^|`)── ' | grep -v -- '^|' || true)
  done
  eq "every candidate SKILL.md holds the banner prefix that the hook reads, in every banner line" "$bad" 0

  bad=0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    q=${r//[^\']/}; [ $(( ${#q} % 2 )) = 0 ] || { echo "FAIL odd quote count: $r"; bad=$((bad+1)); }
    q=${r//[^\"]/}; [ $(( ${#q} % 2 )) = 0 ] || { echo "FAIL odd double quote count: $r"; bad=$((bad+1)); }
    [ "$(printf '%s' "${r//[^(]/}" | wc -c | tr -d ' ')" = "$(printf '%s' "${r//[^)]/}" | wc -c | tr -d ' ')" ] || { echo "FAIL unbalanced parenthesis: $r"; bad=$((bad+1)); }
  done < <(printf '%s\n' "$cat" | jq -r .reason)
  eq "every real reason has balanced quotes and parentheses" "$bad" 0

  bad=0
  while IFS=$'\t' read -r n d r; do
    [ "$(clean_end "$d" "$r")" = true ] || { echo "FAIL reason does not end at a clause boundary: $n: $r"; bad=$((bad+1)); }
  done < <(printf '%s\n' "$cat" | jq -r '[.name, .description, .reason] | @tsv')
  eq "every real reason is empty or ends at a clause boundary of its description" "$bad" 0

  d=$(printf '%s\n' "$cat" | jq -r 'select(.name == "design") | .description')
  eq "the clean-end check rejects the design cut" "$(clean_end "$d" "Produce a shareable system-design document (with diagrams) from a high-level.")" false
  d=$(printf '%s\n' "$cat" | jq -r 'select(.name == "gather") | .description')
  eq "the clean-end check rejects the gather cut" "$(clean_end "$d" "Use it when you have a PRD, product brief, or research doc that needs iterative.")" false
  d=$(printf '%s\n' "$cat" | jq -r 'select(.name == "consilium") | .description')
  eq "the clean-end check rejects the consilium cut" "$(clean_end "$d" "Use it when the user explicitly invokes /bf:consilium or another bf skill calls.")" false
  eq "the clean-end check accepts a cut at a comma" "$(clean_end "Use when a, b, c" "Use it when a, b.")" true
  eq "the clean-end check accepts an empty reason" "$(clean_end "Use when a long thing" "")" true

  bad=0
  while IFS= read -r r; do
    printf '%s' "$r" | bash "$hooks/../skills/plain/scripts/prose-lint.sh" - --mode chat --format json >/dev/null 2>&1 || { echo "FAIL prose lint: $r"; bad=$((bad+1)); }
  done < <(printf '%s\n' "$cat" | jq -r '"Tip: /bf:" + .name + " fits this." + (if .reason != "" then " " + .reason else "" end)')
  eq "every real tip passes the prose lint" "$bad" 0
}

cases_docs() {
  local readme row
  readme=$(awk '/^## /{t=($0=="## Skill-suggestion hook")} t' "$hooks/../README.md")
  row=$(grep -F 'skill-suggest-stop.sh' "$hooks/../skills/typesafe/SKILL.md")
  eq "the README section exists" "$(printf '%s' "$readme" | head -n 1)" "## Skill-suggestion hook"
  eq "the typesafe row exists in the existing cell form" "$(printf '%s' "$row" | cut -c1-37)" '| `/bf:*` — `skill-suggest-stop.sh` |'
  eq "the docs copy no limit value of the hook" "$( { printf '%s\n%s\n' "$readme" "$row" | grep -cE '4000|2000|0[.]8|0[.]6|2097152|5242880'; } | tr -d ' ')" 0
}

main() {
  cases_layout
  cases_guards
  cases_registration
  cases_scan
  cases_catalog
  cases_ask
  cases_fallback
  cases_unavailable
  cases_tip
  cases_dedupe
  cases_log
  cases_real_skills
  cases_docs
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
