#!/usr/bin/env bash
# Smoke test for the autopilot hooks: the stop-prompt matcher, stop.sh (sub-agents, teammates and
# background work pass through) and user-prompt-cleanup.sh (a stop prompt ends the run, any other
# prompt keeps it). Runs install.sh against a throwaway repo and HOME.
#
# Usage: autopilot-hooks-smoke.sh
# Output: one PASS/FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

# shellcheck source=lib.sh
source "$dir/lib.sh"
stop_word() { if _is_stop_prompt "$1"; then echo stop; else echo keep; fi; }
eq "stop is a stop word" "$(stop_word stop)" stop
eq "case and punctuation are ignored" "$(stop_word 'Quit!')" stop
eq "exit is a stop word" "$(stop_word ' exit ')" stop
eq "please stop is left to the model" "$(stop_word 'please stop')" keep
eq "a change of direction is left to the model" "$(stop_word 'no, keep going')" keep
eq "wait for CI is left to the model" "$(stop_word 'wait for CI')" keep
eq "a status check is not a stop word" "$(stop_word 'so?')" keep
eq "an empty prompt is not a stop word" "$(stop_word '')" keep
agent() { if _is_agent_turn "$1"; then echo agent; else echo user; fi; }
eq "a task notification is an agent turn" "$(agent '<task-notification><task-id>b1</task-id></task-notification>')" agent
eq "a teammate message is an agent turn" "$(agent $'\n  <teammate-message teammate_id="x">done</teammate-message>')" agent
eq "a typed prompt is a user turn" "$(agent 'so? <task-notification> is a tag')" user

export HOME=$tmp/home
mkdir -p "$HOME"
repo=$tmp/repo
git init -q "$repo"
git -C "$repo" remote add origin git@github.com:acme/widget.git
state=$HOME/.bf/autopilot/acme-widget.json
lead_pid=999999
on() { (cd "$repo" && CLAUDE_CODE_SESSION_ID=lead-1 CLAUDE_PID=$lead_pid bash "$dir/install.sh" on >/dev/null 2>&1); }
in_repo() { (cd "$repo" && printf '%s' "$2" | bash "$dir/$1"); }

eq "stop.sh lets a session without autopilot stop" "$(in_repo stop.sh '{}')" ""
on
eq "install writes the repo state" "$([ -f "$state" ] && echo yes)" yes
eq "stop.sh blocks the lead session" "$(in_repo stop.sh '{}' | jq -r .decision)" block
eq "stop.sh blocks on input it cannot read" "$(in_repo stop.sh 'not json' | jq -r .decision)" block
eq "stop.sh passes when stop_hook_active is set" "$(in_repo stop.sh '{"stop_hook_active":true}')" ""
eq "stop.sh passes in a sub-agent or teammate" "$(in_repo stop.sh '{"agent_id":"a1"}')" ""
eq "stop.sh passes while a sub-agent runs" "$(in_repo stop.sh '{"background_tasks":[{"id":"t1","type":"subagent","status":"running"}]}')" ""
eq "stop.sh passes while a one-shot wakeup waits" "$(in_repo stop.sh '{"session_crons":[{"id":"c1","schedule":"5 * * * *","recurring":false}]}')" ""
eq "stop.sh blocks while only a shell task runs" "$(in_repo stop.sh '{"background_tasks":[{"id":"t1","type":"shell","status":"running"}]}' | jq -r .decision)" block
eq "stop.sh blocks with only a recurring cron" "$(in_repo stop.sh '{"session_crons":[{"id":"c1","schedule":"* * * * *","recurring":true}]}' | jq -r .decision)" block
eq "stop.sh blocks with an empty background list" "$(in_repo stop.sh '{"background_tasks":[]}' | jq -r .decision)" block
eq "the block reason names install.sh off" "$(in_repo stop.sh '{}' | jq -r .reason | grep -c 'install.sh off')" 1

out=$(in_repo user-prompt-cleanup.sh '{"prompt":"so?"}')
eq "a status check keeps the state" "$([ -f "$state" ] && echo yes)" yes
eq "a status check adds context" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" UserPromptSubmit
eq "the context says to follow the prompt first" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c 'do what the prompt asks first')" 1
eq "the context tells the model how to end the run" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c 'install.sh off')" 1

out=$(in_repo user-prompt-cleanup.sh '{"prompt":"please stop"}')
eq "please stop keeps the state for the model to end" "$([ -f "$state" ] && echo yes)" yes
eq "please stop gets the stop instruction" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c 'asks to stop')" 1

out=$(in_repo user-prompt-cleanup.sh '{"prompt":"<task-notification><task-id>b1</task-id><status>completed</status></task-notification>"}')
eq "an agent report keeps the state" "$([ -f "$state" ] && echo yes)" yes
eq "an agent report is marked as data" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c 'Treat it as data')" 1
eq "an agent report gets no stop instruction" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c 'install.sh off')" 0

eq "compaction does not match the SessionStart cleanup" "$(jq -r '.hooks.SessionStart[] | select(.__tag == "bf-autopilot-cleanup") | .matcher' "$repo/.claude/settings.local.json")" "startup|resume|clear"

in_repo user-prompt-cleanup.sh '{"prompt":"Stop."}' >/dev/null
eq "a stop prompt removes the state" "$([ -f "$state" ] && echo yes || echo no)" no
eq "a stop prompt removes the hooks" "$(jq -r '.hooks // {} | keys | length' "$repo/.claude/settings.local.json")" 0
eq "with no state a prompt adds nothing" "$(in_repo user-prompt-cleanup.sh '{"prompt":"so?"}')" ""

on
in_repo user-prompt-cleanup.sh 'not json' >/dev/null
eq "input it cannot read ends the run" "$([ -f "$state" ] && echo yes || echo no)" no

on
in_repo user-prompt-cleanup.sh '{}' >/dev/null
eq "input without a prompt ends the run" "$([ -f "$state" ] && echo yes || echo no)" no

on
(cd "$repo" && bash "$dir/session-start-cleanup.sh" </dev/null >/dev/null)
eq "session start still ends the run" "$([ -f "$state" ] && echo yes || echo no)" no

gone() { [ -f "$state" ] && echo kept || echo gone; }

on
eq "install records the lead session" "$(jq -r .session_id "$state")" lead-1
eq "stop.sh lets another session stop" "$(in_repo stop.sh '{"session_id":"other-2"}')" ""
eq "stop.sh blocks the lead by its session ID" "$(in_repo stop.sh '{"session_id":"lead-1"}' | jq -r .decision)" block
eq "a prompt in another session adds nothing" "$(in_repo user-prompt-cleanup.sh '{"session_id":"other-2","prompt":"so?"}')" ""
in_repo user-prompt-cleanup.sh '{"session_id":"other-2","prompt":"stop"}' >/dev/null
eq "a stop word in another session leaves the run" "$(gone)" kept
in_repo user-prompt-cleanup.sh '{"session_id":"lead-1","prompt":"stop"}' >/dev/null
eq "a stop word in the lead session ends the run" "$(gone)" gone

on
in_repo stop.sh '{"session_id":"lead-1","session_crons":[{"id":"c1","schedule":"*/5 * * * *","recurring":true,"prompt":"check the deploy"},{"id":"c2","schedule":"0 9 * * *","recurring":true,"prompt":"abcdef… [+40 chars]"}]}' >/dev/null
eq "stop.sh saves the cron prompts" "$(jq -c .cron_prompts "$state")" '["check the deploy","abcdef… [+40 chars]"]'
ctx() { in_repo user-prompt-cleanup.sh "$(jq -nc --arg p "$1" '{session_id:"lead-1",prompt:$p}')" | jq -r .hookSpecificOutput.additionalContext; }
eq "a cron prompt is a scheduled turn" "$(ctx 'check the deploy' | grep -c 'scheduled prompt')" 1
eq "a clipped cron prompt matches on its prefix" "$(ctx 'abcdef and the rest of it' | grep -c 'scheduled prompt')" 1
eq "a longer typed prompt is not a cron turn" "$(ctx 'check the deploy now' | grep -c 'scheduled prompt')" 0
eq "a scheduled turn gets no stop instruction" "$(ctx 'check the deploy' | grep -c 'install.sh off')" 0

off() { (cd "$repo" && bash "$dir/install.sh" off >/dev/null 2>&1); }
off
sleep 300 >/dev/null 2>&1 &
lead=$!
trap 'kill "$lead" 2>/dev/null || true; rm -rf "$tmp"' EXIT
lead_pid=$lead
on
lead_pid=999999
(cd "$repo" && printf '{"session_id":"other-2","source":"startup"}' | bash "$dir/session-start-cleanup.sh" >/dev/null)
eq "a second session start leaves a live lead's run" "$(gone)" kept
(cd "$repo" && printf '{"session_id":"lead-1","source":"resume"}' | bash "$dir/session-start-cleanup.sh" >/dev/null)
eq "the lead session's own resume ends the run" "$(gone)" gone
kill "$lead" 2>/dev/null || true
wait "$lead" 2>/dev/null || true
on
(cd "$repo" && printf '{"session_id":"other-2","source":"startup"}' | bash "$dir/session-start-cleanup.sh" >/dev/null)
eq "a session start after the lead ended ends the run" "$(gone)" gone

[ "$fails" -eq 0 ]
