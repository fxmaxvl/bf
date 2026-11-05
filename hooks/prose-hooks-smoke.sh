#!/usr/bin/env bash
# Smoke test for the prose hooks. Runs each hook script with sample hook input in a throwaway HOME and repo.
#
# Usage: prose-hooks-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

hooks=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

dash=$'\xE2\x80\x94'
home=$tmp/home
repo=$tmp/repo
plain=$tmp/plain
gone=$tmp/does-not-exist
mkdir -p "$home" "$plain" "$repo/.bf/conventions"
git init -q "$repo"
cat > "$repo/.bf/conventions/prose.md" <<'MD'
# Project prose

## Self-lint

PROJECT-OVERRIDE-ITEM

## Other
MD

# hook <script> <input json> [VAR=value...]: runs one hook with CLAUDE_PLUGIN_ROOT unset. Sets out and rc.
out= rc=0
hook() {
  local script=$1 input=$2; shift 2
  rc=0
  out=$(printf '%s' "$input" | env -u CLAUDE_PLUGIN_ROOT HOME="$home" GIT_CEILING_DIRECTORIES="$tmp" "$@" bash "$hooks/$script" 2>/dev/null) || rc=$?
}
input() { jq -cn --arg cwd "$1" '{cwd:$cwd}'; }

# SessionStart
hook prose-session-start.sh "$(input "$repo")" BF_PROSE_HOOK=off
eq "off switch output" "$out" ""; eq "off switch exit" "$rc" 0
hook prose-session-start.sh "$(input "$repo")"
eq "session start event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" SessionStart
eq "session start uses project override" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" "PROJECT-OVERRIDE-ITEM"
hook prose-session-start.sh "$(input "$plain")"
eq "session start plugin items" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c '^[1-8]\. ')" 8
hook prose-session-start.sh "not json"
eq "bad json output" "$out" ""; eq "bad json exit" "$rc" 0
hook prose-session-start.sh "$(input "$gone")"
eq "no lint result output" "$out" ""; eq "no lint result exit" "$rc" 0


# PostToolUse
mkdir -p "$tmp/conventions"
repo2=$tmp/conventions/repo2
git init -q "$repo2"
write_in() { jq -cn --arg cwd "$1" --arg tool "$2" --arg p "$3" --arg k "$4" --arg t "$5" \
  '{cwd:$cwd, tool_name:$tool, tool_input:({file_path:$p} + {($k):$t})}'; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out"; }

hook prose-post-write.sh "$(write_in "$repo" Write "$repo/README.md" content "A${dash}B.")"
eq "post-write event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" PostToolUse
eq "post-write md em dash" "$(ctx | grep -c '1 em dash')" 1
eq "post-write note names the path" "$(ctx | grep -c "$repo/README.md")" 1
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/skills/x/SKILL.md" content "A${dash}B.")"
eq "post-write SKILL.md skipped" "$out" ""
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/.bf/conventions/prose.md" content "A${dash}B.")"
eq "post-write conventions skipped" "$out" ""
hook prose-post-write.sh "$(write_in "$repo2" Write "$repo2/README.md" content "A${dash}B.")"
eq "post-write parent conventions dir not skipped" "$(ctx | grep -c '1 em dash')" 1
hook prose-post-write.sh "$(write_in "$repo" Edit "$repo/README.md" new_string "clean text.")"
eq "post-write edit clean new_string" "$out" ""
hook prose-post-write.sh "$(write_in "$repo" Edit "$repo/README.md" new_string "one; two")"
eq "post-write edit hit" "$(ctx | grep -c '1 semicolon')" 1
eq "post-write edit fence warning" "$(ctx | grep -c 'code fence')" 1
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/a.ts" content $'  #count = 0;\nconst x = 1;')"
eq "post-write ts private field" "$out" ""
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/a.sh" content $'echo hi\n# one; two')"
eq "post-write sh comment hit" "$(ctx | grep -c '1 semicolon')" 1
hook prose-post-write.sh "$(write_in "$repo" Write "$repo/a.json" content "A${dash}B")"
eq "post-write json skipped" "$out" ""
hook prose-post-write.sh "$(write_in "$gone" Write "$gone/README.md" content "A${dash}B.")"
eq "post-write no lint result output" "$out" ""; eq "post-write no lint result exit" "$rc" 0
hook prose-post-write.sh "$(write_in "$repo" Read "$repo/README.md" content "A${dash}B.")"
eq "post-write other tool" "$out" ""


# PreToolUse
bash_in() { jq -cn --arg cwd "$1" --arg c "$2" '{cwd:$cwd, tool_name:"Bash", tool_input:{command:$c}}'; }
semi_note() { hook prose-pre-bash.sh "$(bash_in "$repo" "$2")"; eq "pre-bash $1" "$(ctx | grep -c '1 semicolon')" 1; }
semi_note "git commit -m" 'git commit -m "a; b"'
semi_note "git commit -m single quotes" "git commit -m 'a; b'"
semi_note "git commit --message" 'git commit --message "a; b"'
semi_note "git commit --message=" 'git commit --message="a; b"'
semi_note "git commit -am" 'git commit -am "a; b"'
semi_note "git commit escaped quote" 'git commit -m "say \"x\"; y"'
semi_note "git commit after other command" 'git add a && git commit -m "a; b"'
semi_note "gh pr create --body" 'gh pr create --body "a; b"'
semi_note "gh pr create --body=" 'gh pr create --body="a; b"'
semi_note "gh pr create -b" 'gh pr create -b "a; b"'
semi_note "gh pr create --title" 'gh pr create --title "a; b"'
semi_note "gh pr create --body-file with plain title" 'gh pr create --body-file x.md --title "a; b"'
semi_note "finalize --commit-msg" 'bash "$P/finalize-git.sh" --commit-msg "a; b"'
semi_note "finalize --pr-title" 'bash "$P/finalize-git.sh" --pr-title "a; b"'
semi_note "finalize --pr-body" 'bash "$P/finalize-git.sh" --pr-body "a; b"'
hook prose-pre-bash.sh "$(bash_in "$repo" 'git commit -m "a; b"')"
eq "pre-bash event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" PreToolUse
eq "pre-bash no permissionDecision" "$(jq -r '.hookSpecificOutput | has("permissionDecision")' <<<"$out")" false
eq "pre-bash no top-level decision" "$(jq -r 'has("decision")' <<<"$out")" false
hook prose-pre-bash.sh "$(bash_in "$repo" 'git commit -m"a; b"')"
eq "pre-bash glued value skipped" "$out" ""
hook prose-pre-bash.sh "$(bash_in "$repo" 'git commit -m a; ls')"
eq "pre-bash unquoted value skipped" "$out" ""
hook prose-pre-bash.sh "$(bash_in "$repo" 'git commit -F msg.txt')"
eq "pre-bash -F skipped" "$out" ""
hook prose-pre-bash.sh "$(bash_in "$repo" $'git commit -m "$(cat <<\'EOF\'\nfix: a; b\nEOF\n)"')"
eq "pre-bash heredoc commit skipped" "$out" ""
hook prose-pre-bash.sh "$(bash_in "$repo" $'bash x/finalize-git.sh --commit-msg "fix: a; b" --pr-title "t '"$dash"$' u" --pr-body "$(cat <<\'EOF\'\nIt\'s done\nEOF\n)"')"
eq "pre-bash finalize lints message and title, skips body" "$(ctx | grep -c '1 em dash, 1 semicolon, ')" 1
eq "pre-bash finalize skipped body has no contraction" "$(ctx | grep -c contraction)" 0
hook prose-pre-bash.sh "$(bash_in "$repo" 'git status')"
eq "pre-bash other command" "$out" ""
hook prose-pre-bash.sh "$(bash_in "$repo" 'git commit -m "clean message"')"
eq "pre-bash clean message" "$out" ""
hook prose-pre-bash.sh "$(bash_in "$repo" 'git commit -m "unbalanced; quote')"
eq "pre-bash parse failure" "$out" ""; eq "pre-bash parse failure exit" "$rc" 0
hook prose-pre-bash.sh "$(bash_in "$gone" 'git commit -m "a; b"')"
eq "pre-bash no lint result output" "$out" ""; eq "pre-bash no lint result exit" "$rc" 0


# Stop and UserPromptSubmit record
uid=$(id -u)
recroot=$tmp/rec
recdir=$recroot/bf-prose-$uid
stop_in() { jq -cn --arg cwd "$1" --arg s "$2" --arg m "$3" '{cwd:$cwd, session_id:$s, last_assistant_message:$m}'; }
prompt_in() { jq -cn --arg s "$1" '{cwd:"/", session_id:$s, prompt:"hi"}'; }
nwords() { local i=0 w=; while [ "$i" -lt "$1" ]; do w="$w word"; i=$((i+1)); done; printf '%s' "${w# }"; }
rec() { BF_PROSE_RECORD_ROOT=$recroot "$@"; }

hook prose-stop.sh "$(stop_in "$repo" s1 "A${dash}B is done.")" BF_PROSE_RECORD_ROOT=$recroot
eq "stop prints nothing" "$out" ""
eq "stop writes the record" "$(test -f "$recdir/s1" && echo yes)" yes
eq "record dir mode" "$(ls -ld "$recdir" | cut -c1-10)" "drwx------"
hook prose-user-prompt.sh "$(prompt_in s1)" BF_PROSE_RECORD_ROOT=$recroot
eq "prompt event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" UserPromptSubmit
eq "prompt note" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" "last reply: 1 em dash, 3 words"
eq "record deleted after take" "$(test -f "$recdir/s1" && echo yes || echo no)" no
hook prose-user-prompt.sh "$(prompt_in s1)" BF_PROSE_RECORD_ROOT=$recroot
eq "second prompt prints nothing" "$out" ""
hook prose-stop.sh "$(stop_in "$repo" s2 "$(nwords 200).")" BF_PROSE_RECORD_ROOT=$recroot
eq "long reply writes a record" "$(test -f "$recdir/s2" && echo yes)" yes
hook prose-stop.sh "$(stop_in "$repo" s2 "Short and clean.")" BF_PROSE_RECORD_ROOT=$recroot
eq "clean reply clears the record" "$(test -f "$recdir/s2" && echo yes || echo no)" no
hook prose-stop.sh "$(stop_in "$repo" s3 "A${dash}B.")" BF_PROSE_RECORD_ROOT=$recroot
hook prose-stop.sh "$(stop_in "$repo" s3 "one; two")" BF_PROSE_RECORD_ROOT=$recroot
eq "second stop overwrites" "$(cat "$recdir/s3")" "1 semicolon, 2 words"
hook prose-stop.sh "$(stop_in "$repo" "../../x" "one; two")" BF_PROSE_RECORD_ROOT=$recroot
eq "session id is sanitized" "$(test -f "$recdir/x" && echo yes)" yes
eq "nothing escapes the record dir" "$(test -e "$tmp/x" && echo yes || echo no)" no
before=$(find "$recroot" -type f | wc -l | tr -d ' ')
hook prose-stop.sh "$(stop_in "$repo" "///" "one; two")" BF_PROSE_RECORD_ROOT=$recroot
eq "empty session id writes nothing" "$(find "$recroot" -type f | wc -l | tr -d ' ')" "$before"
hook prose-stop.sh "$(stop_in "$repo" s4 "one; two")" BF_PROSE_RECORD_ROOT=$tmp/rec2 BF_PROSE_UID=99999
eq "foreign owner writes nothing" "$(find "$tmp/rec2" -type f 2>/dev/null | wc -l | tr -d ' ')" 0
eq "foreign owner exit" "$rc" 0
hook prose-stop.sh "$(stop_in "$gone" s5 "one; two")" BF_PROSE_RECORD_ROOT=$recroot
eq "stop no lint result output" "$out" ""; eq "stop no lint result exit" "$rc" 0
eq "stop no lint result writes nothing" "$(test -f "$recdir/s5" && echo yes || echo no)" no
hook prose-user-prompt.sh "$(prompt_in nothing)" BF_PROSE_RECORD_ROOT=$recroot
eq "prompt without record" "$out" ""; eq "prompt without record exit" "$rc" 0


# SubagentStop
sub_in() { jq -cn --arg cwd "$1" --arg m "$2" --argjson a "$3" '{cwd:$cwd, last_assistant_message:$m, stop_hook_active:$a}'; }
hook prose-subagent-stop.sh "$(sub_in "$plain" "one; two" false)"
eq "subagent block decision" "$(jq -r .decision <<<"$out")" block
eq "subagent reason names the count" "$(jq -r .reason <<<"$out" | grep -c '1 semicolon')" 1
eq "subagent block is top-level" "$(jq -r 'has("hookSpecificOutput")' <<<"$out")" false
eq "subagent block exit" "$rc" 0
hook prose-subagent-stop.sh "$(sub_in "$plain" "one; two" true)"
eq "subagent stop_hook_active guard" "$out" ""
hook prose-subagent-stop.sh "$(sub_in "$repo" "one; two" false)"
eq "subagent no block without prose-lint block" "$out" ""
hook prose-subagent-stop.sh "$(sub_in "$plain" "$(nwords 300)." false)"
eq "subagent long reply alone does not block" "$out" ""
hook prose-subagent-stop.sh "$(sub_in "$gone" "one; two" false)"
eq "subagent no lint result output" "$out" ""; eq "subagent no lint result exit" "$rc" 0


# hooks.json wiring
cfg=$hooks/hooks.json
eq "hooks.json parses" "$(jq -e . "$cfg" >/dev/null 2>&1 && echo yes)" yes
eq "hooks.json events" "$(jq -r '.hooks | keys | join(",")' "$cfg")" "PostToolUse,PreToolUse,SessionStart,Stop,SubagentStop,UserPromptSubmit"
eq "hooks.json timeouts" "$(jq -r '[.hooks[][].hooks[].timeout] | unique | join(",")' "$cfg")" 5
eq "hooks.json matchers" "$(jq -r '[.hooks.SessionStart[0].matcher, .hooks.PostToolUse[0].matcher, .hooks.PreToolUse[0].matcher, (.hooks.Stop[0] | has("matcher")), (.hooks.SubagentStop[0] | has("matcher"))] | join(",")' "$cfg")" "compact,Write|Edit,Bash,false,false"
missing=0
for s in $(jq -r '.hooks[][].hooks[].command' "$cfg" | sed 's/.*hooks\/\(prose-[a-z-]*\.sh\).*/\1/'); do
  [ -f "$hooks/$s" ] || missing=$((missing+1))
done
eq "hooks.json scripts exist" "$missing" 0
eq "hooks.json script count" "$(jq -r '[.hooks[][].hooks[]] | length' "$cfg")" 6

# off switch for all six hooks, with dirty input
dirty="A${dash}B; it's"
off_ok=0
for pair in \
  "prose-session-start.sh|$(input "$repo")" \
  "prose-post-write.sh|$(write_in "$repo" Write "$repo/README.md" content "$dirty")" \
  "prose-pre-bash.sh|$(bash_in "$repo" "git commit -m \"$dirty\"")" \
  "prose-stop.sh|$(stop_in "$repo" soff "$dirty")" \
  "prose-user-prompt.sh|$(prompt_in soff)" \
  "prose-subagent-stop.sh|$(sub_in "$plain" "$dirty" false)"; do
  hook "${pair%%|*}" "${pair#*|}" BF_PROSE_HOOK=off BF_PROSE_RECORD_ROOT=$recroot
  if [ -z "$out" ] && [ "$rc" -eq 0 ]; then off_ok=$((off_ok+1)); fi
done
eq "off switch silences all six hooks" "$off_ok" 6
eq "off switch writes no record" "$(test -f "$recdir/soff" && echo yes || echo no)" no

[ "$fails" -eq 0 ]
