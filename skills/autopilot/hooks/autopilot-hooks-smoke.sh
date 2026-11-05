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
eq "stop is a stop prompt" "$(stop_word stop)" stop
eq "case and punctuation are ignored" "$(stop_word 'Hold on!')" stop
eq "a contraction counts as one word" "$(stop_word "no, don't push")" stop
eq "a curly apostrophe counts as one word" "$(stop_word "no, don’t push")" stop
eq "a status check is not a stop prompt" "$(stop_word 'so?')" keep
eq "continue is not a stop prompt" "$(stop_word continue)" keep
eq "a stop word later in the prompt does not stop" "$(stop_word "don't stop the tests")" keep
eq "a long prompt that starts with a stop word does not stop" "$(stop_word 'stop words in the doc')" keep
eq "pause is not a stop word" "$(stop_word pause)" keep
eq "an empty prompt is not a stop prompt" "$(stop_word '')" keep

export HOME=$tmp/home
mkdir -p "$HOME"
repo=$tmp/repo
git init -q "$repo"
git -C "$repo" remote add origin git@github.com:acme/widget.git
state=$HOME/.bf/autopilot/acme-widget.json
on() { (cd "$repo" && bash "$dir/install.sh" on >/dev/null 2>&1); }
in_repo() { (cd "$repo" && printf '%s' "$2" | bash "$dir/$1"); }

eq "stop.sh lets a session without autopilot stop" "$(in_repo stop.sh '{}')" ""
on
eq "install writes the repo state" "$([ -f "$state" ] && echo yes)" yes
eq "stop.sh blocks the lead session" "$(in_repo stop.sh '{}' | jq -r .decision)" block
eq "stop.sh blocks on input it cannot read" "$(in_repo stop.sh 'not json' | jq -r .decision)" block
eq "stop.sh passes when stop_hook_active is set" "$(in_repo stop.sh '{"stop_hook_active":true}')" ""
eq "stop.sh passes in a sub-agent or teammate" "$(in_repo stop.sh '{"agent_id":"a1"}')" ""
eq "stop.sh passes while background work runs" "$(in_repo stop.sh '{"background_tasks":[{"id":"t1","type":"shell","status":"running"}]}')" ""
eq "stop.sh blocks with an empty background list" "$(in_repo stop.sh '{"background_tasks":[]}' | jq -r .decision)" block

out=$(in_repo user-prompt-cleanup.sh '{"prompt":"so?"}')
eq "a status check keeps the state" "$([ -f "$state" ] && echo yes)" yes
eq "a status check adds context" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" UserPromptSubmit
eq "the context says to follow the prompt first" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" | grep -c 'Do what this prompt asks first')" 1

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

[ "$fails" -eq 0 ]
