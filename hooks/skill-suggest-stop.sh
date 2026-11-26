#!/usr/bin/env bash
# Stop hook: show one tip line that names a bf skill that fits the next step of the session. It costs no
# Claude tokens and never adds a Claude turn. It exits 0 on every path, because Claude Code reads exit 2
# from a Stop hook as a block.
#
# Usage: hook input JSON on stdin
# Output: none, or one JSON object with a systemMessage key.
set -uo pipefail

# Found from this file, never from CLAUDE_PLUGIN_ROOT, so the hook also runs outside Claude Code.
hooks_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# prose-lib.sh sets the EXIT trap that turns every failure into exit 0. Do not replace the trap.
# shellcheck source=prose-lib.sh
. "$hooks_dir/prose-lib.sh"

# Every limit of the hook is here, so the docs can describe them in words and need no copy of a number.
SUGGEST_BANNER_PREFIX='── bf:'
SUGGEST_TAIL_BYTES=${BF_SUGGEST_TAIL_BYTES:-2097152}
SUGGEST_WINDOW_PROMPTS=3
SUGGEST_PROMPT_CHARS=2000

# suggest_has_banner <text>: succeeds when the text holds the banner prefix. The prefix is the other side
# of a contract with every top-level skills/*/SKILL.md that prints a banner. A skill that prints a
# different form is invisible to the hook, which then suggests a skill while one runs.
suggest_has_banner() { case $1 in *"$SUGGEST_BANNER_PREFIX"*) return 0 ;; *) return 1 ;; esac; }

# suggest_transcript_scan <transcript_path>: prints {"state": "inside" | "free", "prompt": "<last user prompt>"}.
# This is the only function that knows the shape of the Claude Code transcript JSONL. The fixture
# hooks/fixtures/skill-suggest-transcript.jsonl and the cases in hooks/skill-suggest-smoke.sh test it.
suggest_transcript_scan() {
  local path=$1 size out
  if [ ! -r "$path" ] || [ ! -f "$path" ]; then
    printf '{"state":"free","prompt":""}\n'
    return 0
  fi
  size=$(wc -c < "$path" | tr -d ' ')
  if [ "${size:-0}" -le "$SUGGEST_TAIL_BYTES" ]; then
    out=$(jq -nR --argjson start true --argjson n "$SUGGEST_WINDOW_PROMPTS" --argjson cap "$SUGGEST_PROMPT_CHARS" "$SUGGEST_SCAN_JQ" < "$path" 2>/dev/null)
  else
    # The first line of a tail is cut in the middle, so it goes.
    out=$(tail -c "$SUGGEST_TAIL_BYTES" "$path" | tail -n +2 | jq -nR --argjson start false --argjson n "$SUGGEST_WINDOW_PROMPTS" --argjson cap "$SUGGEST_PROMPT_CHARS" "$SUGGEST_SCAN_JQ" 2>/dev/null)
  fi
  [ -n "$out" ] || out='{"state":"free","prompt":""}'
  printf '%s\n' "$out"
}

# The jq program of suggest_transcript_scan. A line that fails to parse is skipped, so a truncated last
# line does not fail the scan. A /clear marker ends the walk back, and the part before it does not count.
# One long skill run writes a line per tool call, so its invocation can sit before the tail that was read.
# When the tail did not reach the start and holds fewer prompts than the window, the state is "inside".
SUGGEST_SCAN_JQ='
def content: (try .message.content catch null);
def text: (content) as $c
  | if ($c | type) == "string" then $c
    elif ($c | type) == "array" then ([$c[] | select(type == "object" and .type == "text") | (.text // "")] | join("\n"))
    else "" end;
def prompt: .type == "user" and (.isMeta != true)
  and (((content) | type) != "array" or ([(content)[] | select(type == "object" and .type == "tool_result")] | length) == 0);
def clear: .type == "user" and ((content) | type) == "string" and ((content) | contains("<command-name>/clear</command-name>"));
def bfcmd: .type == "user" and ((content) | type) == "string" and ((content) | contains("<command-name>/bf:"));
def bfskill: .type == "assistant" and ((content) | type) == "array"
  and ([(content)[] | select(type == "object" and .type == "tool_use" and .name == "Skill" and (((.input.skill // "") | tostring) | startswith("bf:")))] | length) > 0;
[inputs | fromjson? | select(type == "object")] as $all
| ([range(0; $all | length) | select($all[.] | clear)] | last) as $c
| (if $c == null then $all else $all[($c + 1):] end) as $region
| (if $c == null then $start else true end) as $reached
| [range(0; $region | length) | select($region[.] | prompt)] as $p
| (if ($p | length) >= $n then $p[-$n] else 0 end) as $from
| ($region[$from:]) as $win
| ([$win[] | select(bfcmd or bfskill)] | length > 0) as $hit
| {state: (if $hit or ($reached | not) and ($p | length) < $n then "inside" else "free" end),
   prompt: (if ($p | length) > 0 then ($region[$p[-1]] | text | .[0:$cap]) else "" end)}
' 

suggest_main() {
  [ "${BF_SUGGEST_HOOK:-}" = off ] && exit 0
  prose_read_input
  local sid agent active reply transcript scan
  sid=$(prose_field .session_id)
  [ -n "$sid" ] || exit 0
  agent=$(prose_field .agent_id)
  [ -z "$agent" ] || exit 0
  active=$(prose_field .stop_hook_active)
  [ "$active" != true ] || exit 0
  reply=$(prose_field .last_assistant_message)
  suggest_has_banner "$reply" && exit 0
  transcript=$(prose_field .transcript_path)
  scan=$(suggest_transcript_scan "$transcript")
  [ "$(printf '%s' "$scan" | jq -r .state 2>/dev/null)" != inside ] || exit 0
  exit 0
}

# Run only when executed. A smoke case sources the file to call one function.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then suggest_main; fi
