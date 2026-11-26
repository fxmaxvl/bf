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
SUGGEST_REASON_CHARS=80
SUGGEST_REPLY_CHARS=4000
SUGGEST_ASK_TIMEOUT=4
SUGGEST_HELPS_BAR=0.6
SUGGEST_PICK_BAR=0.8
SUGGEST_MIN_PHRASES=2
SUGGEST_SKILLS_ROOT=${BF_SUGGEST_SKILLS_ROOT:-$hooks_dir/../skills}
SUGGEST_TS_ASK=${TYPESAFE_ASK:-$hooks_dir/../skills/typesafe/scripts/typesafe-ask.sh}

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

# The jq program of suggest_catalog. It turns one tab-separated row (name, description, suggest) into one
# catalog entry. The reason is the first clause of the description, cut at a word, with no open quote or
# open parenthesis at the cut. A contraction or a dash that the cut leaves in the clause empties the reason,
# because the tip text must pass the prose rules. A contraction is a letter before the apostrophe, so the
# opening quote of a trigger phrase such as 'research X' is not one.
read -r -d '' SUGGEST_CATALOG_JQ <<'JQ' || true
def trim: sub("[ ,]+$"; "");
def lastat($re): ([match($re; "g")] | last) as $m | if $m == null then null else $m.offset end;
def unclosed_quote:
  ([match("(^|[ (])(['\"])"; "g")] | last) as $o
  | if $o == null then null
    else ($o.captures[1].string) as $q
      | (.[($o.offset + $o.length):]) as $rest
      | if ($rest | test($q + "(?=[,. )]|$)")) then null else $o.offset end
    end;
def cut_quote: unclosed_quote as $i | if $i == null then . else (.[0:$i] | trim | sub(" (or|and)$"; "")) end;
def cut_paren:
  ((gsub("[^(]"; "") | length) > (gsub("[^)]"; "") | length)) as $open
  | if $open then (lastat("\\(")) as $i | (.[0:$i] | trim) else . end;
def settle: (cut_paren | cut_quote) as $n | if $n == . then . else ($n | settle) end;
def has_phrase: test("(^|[ (])['\"]");
def first_clause:
  ([match("—|;|\\. (?=[A-Z])")] | first) as $m | if $m == null then . else .[0:$m.offset] end;
def drop_dangling:
  if test(" (a|an|the|or|and|to|of|in|on|for|with|its|that|you|your|is|are|as|by|from|how|when|who|which)$")
  then (sub(" [^ ]*$"; "") | drop_dangling) else . end;
# A cut at a word prefers the last comma, then drops a function word that the cut leaves at the end.
def word_cut($max):
  if length > $max
  then (.[0:$max]) as $h
    | (if .[$max:($max + 1)] == " " then $h else ($h | sub(" [^ ]*$"; "")) end) as $w
    | (if ($w | test("^.{50,},")) then ($w | sub(",[^,]*$"; "")) else ($w | drop_dangling) end)
  else . end;
def reason($max):
  (if startswith("Use when") then "Use it when" + .[8:] else . end)
  | first_clause | trim | word_cut($max) | trim
  | . as $pre | settle
  | (if ($pre | has_phrase) and (has_phrase | not) and ($pre != .) then "" else . end)
  | sub("[. ,]+$"; "")
  | if . == "" or test("—|;|[A-Za-z](n['’]t|['’](re|ve|ll|m|d))([^A-Za-z]|$)") then "" else . + "." end;
def phrases:
  [match("(^|[ (])(['\"])(.+?)\\2(?=[,. )]|$)"; "g") | .captures[2].string | ascii_downcase];
split("\t")
| select(length >= 3 and .[0] != "" and .[2] != "false")
| {name: .[0], description: .[1], reason: (.[1] | reason($max)), phrases: (.[1] | phrases)}
JQ

# suggest_catalog [skills_root]: prints one JSON line per candidate skill: {name, description, reason, phrases}.
# This is the only function that reads SKILL.md frontmatter and the only one that applies the description
# rules, so the file layout stays behind one interface. The description shape it expects is "Use when ..."
# first, with trigger phrases in single or double quotes, as skills/write-skill/SKILL.md asks. The
# frontmatter reader in skills/self-audit/scripts/audit-static.sh is the other parser: keep the two in step.
# It reads only skills/*/SKILL.md, never a nested phase skill. A skill with suggest: false is left out.
suggest_catalog() {
  local root=${1:-$SUGGEST_SKILLS_ROOT}
  awk '
    function unquote(v,   q) {
      q = substr(v, 1, 1)
      if ((q == "\"" || q == "\047") && length(v) >= 2 && substr(v, length(v), 1) == q) {
        v = substr(v, 2, length(v) - 2)
        if (q == "\"") { gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v) } else gsub(/\047\047/, "\047", v)
      }
      return v
    }
    function flush() { if (seen) { gsub(/\t/, " ", desc); print name "\t" desc "\t" sug } }
    FNR == 1 { flush(); seen = 1; fm = 0; name = ""; desc = ""; sug = "" }
    /^---[ \t]*$/ { fm++; next }
    fm == 1 {
      if (match($0, /^name:[ \t]*/)) name = unquote(substr($0, RLENGTH + 1))
      else if (match($0, /^description:[ \t]*/)) desc = unquote(substr($0, RLENGTH + 1))
      else if (match($0, /^suggest:[ \t]*/)) sug = substr($0, RLENGTH + 1)
    }
    END { flush() }
  ' "$root"/*/SKILL.md 2>/dev/null | jq -Rc --argjson max "$SUGGEST_REASON_CHARS" "$SUGGEST_CATALOG_JQ" 2>/dev/null
}

# suggest_tail <chars>: prints the last chars characters of stdin. jq counts characters, so a multibyte
# character is never split.
suggest_tail() { jq -Rsj --argjson n "$1" '.[-$n:]' 2>/dev/null; }

# suggest_build_questions <catalog>: prints the two questions for TypeSafe. jq builds the JSON, because a
# description holds quotes and dashes.
suggest_build_questions() {
  printf '%s\n' "$1" | jq -s '
    {helps: {type: "noul",
             instructions: "Would one of the bf workflow skills help with what the user is likely to do next?"},
     skill: {type: "choice",
             instructions: "Which bf skill fits what the user is likely to do next?",
             criteria: ((map({(.name): .description}) | add) + {none: "no bf skill fits what the user is likely to do next, or the conversation is casual or finished"})}}'
}

# suggest_build_state <prompt> <reply>: prints the state that TypeSafe judges.
suggest_build_state() { jq -cn --arg p "$1" --arg r "$2" '{user_prompt: $p, reply: $r}'; }

# suggest_ask <catalog> <prompt> <reply>: asks TypeSafe and prints one outcome: "answer<TAB><answers json>",
# "fallback" or "silent". This function owns the exit-code table of skills/typesafe/scripts/typesafe-ask.sh.
# Exit 3 of that script means unavailable (off, no key, timeout, HTTP error, no answers), and only that is
# "fallback". The script also exits 3 when its own input is bad (questions that are not JSON, a missing state
# file, no temp file). Those are bugs of this hook, so the hook checks both files first and answers "silent"
# instead of hiding the bug behind the keyword fallback.
suggest_ask() {
  local q s ans rc=0
  q=$(mktemp "${TMPDIR:-/tmp}/bf-suggest.XXXXXX" 2>/dev/null) || { printf 'silent\n'; return 0; }
  s=$(mktemp "${TMPDIR:-/tmp}/bf-suggest.XXXXXX" 2>/dev/null) || { rm -f "$q"; printf 'silent\n'; return 0; }
  suggest_build_questions "$1" > "$q" 2>/dev/null
  suggest_build_state "$2" "$3" > "$s" 2>/dev/null
  if jq -e . "$q" >/dev/null 2>&1 && jq -e . "$s" >/dev/null 2>&1; then
    ans=$(bash "$SUGGEST_TS_ASK" --questions "$q" --state "$s" --timeout "$SUGGEST_ASK_TIMEOUT" 2>/dev/null) || rc=$?
  else
    rc=2
  fi
  rm -f "$q" "$s"
  case $rc in
    0) # jq 1.6 -e exits 0 on empty input, so test for empty output first.
       if [ -n "$ans" ] && printf '%s' "$ans" | jq -e 'type == "object" and has("helps") and has("skill")' >/dev/null 2>&1
       then printf 'answer\t%s\n' "$ans"; else printf 'silent\n'; fi ;;
    3) printf 'fallback\n' ;;
    *) printf 'silent\n' ;;
  esac
}

# suggest_fallback <catalog> <prompt> <reply>: prints the name of the skill with the most distinct trigger
# phrases in the text, or nothing. It needs the minimum count and no tie. jq contains() matches plain text,
# so a phrase with a regex character is safe.
suggest_fallback() {
  printf '%s\n' "$1" | jq -rs --arg t "$(printf '%s\n%s' "$2" "$3" | tr '[:upper:]' '[:lower:]')" --argjson min "$SUGGEST_MIN_PHRASES" '
    map({name, score: ([.phrases[] | select(. as $p | $t | contains($p))] | unique | length)})
    | sort_by(-.score) as $r
    | if ($r | length) > 0 and $r[0].score >= $min and (($r | length) < 2 or $r[1].score != $r[0].score) then $r[0].name else empty end' 2>/dev/null
}

# suggest_decide <catalog> <source> <payload>: prints the decision object that the tip and the log both read:
# {skill, confidence, source, due, shown, reason}. For source typesafe the payload is the answers JSON. For
# source keyword it is the picked name or an empty string. skill is the name of the chosen skill whenever
# the choice is a catalog name, even when the helps gate or the confidence bar fails, and none otherwise.
# due says that a tip is justified. shown starts false, and suggest_main sets it after the dedupe check.
suggest_decide() {
  local cat
  cat=$(printf '%s\n' "$1" | jq -cs . 2>/dev/null) || return 0
  if [ "$2" = typesafe ]; then
    jq -cn --argjson cat "$cat" --argjson ans "$3" --argjson hb "$SUGGEST_HELPS_BAR" --argjson pb "$SUGGEST_PICK_BAR" '
      ($ans.skill | objects | .choice // "") as $c
      | ([$cat[] | select(.name == $c)] | first) as $hit
      | (if $hit == null then "none" else $c end) as $skill
      | (if ($ans.skill | objects | .confidence | type) == "number" then $ans.skill.confidence else null end) as $conf
      | (if ($ans.helps | objects | .noul | type) == "number" then $ans.helps.noul else 0 end) as $helps
      | {skill: $skill, confidence: $conf, source: "typesafe",
         due: ($skill != "none" and $helps >= $hb and ($conf // 0) >= $pb),
         shown: false, reason: (if $hit == null then "" else $hit.reason end)}' 2>/dev/null
  else
    jq -cn --argjson cat "$cat" --arg n "$3" '
      ([$cat[] | select(.name == $n)] | first) as $hit
      | {skill: (if $hit == null then "none" else $n end), confidence: null, source: "keyword",
         due: ($hit != null), shown: false, reason: (if $hit == null then "" else $hit.reason end)}' 2>/dev/null
  fi
}

# suggest_tip <decision>: prints the hook output. The object holds only systemMessage, so the tip never
# blocks the turn and never adds a model turn.
suggest_tip() {
  printf '%s\n' "$1" | jq -c '{systemMessage: ("Tip: /bf:" + .skill + " fits this." + (if (.reason // "") != "" then " " + .reason else "" end))}'
}

# suggest_record_file <session_id>: prints the path of the record of the session, or fails. It is the only
# place that builds the path, strips the id, and applies the owner and symlink checks. It uses one helper of
# prose-lib.sh, prose_record_dir_ensure, and no other record helper. The record is a per-user 0700 directory
# because a shared /tmp can hold a directory that another user made first.
suggest_record_file() {
  local uid=${BF_SUGGEST_UID:-$(id -u)} sid dir
  sid=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-')
  [ -n "$sid" ] || return 1
  dir=${BF_SUGGEST_RECORD_ROOT:-${TMPDIR:-/tmp}}/bf-suggest-$uid
  prose_record_dir_ensure "$dir" "$uid" || return 1
  [ ! -L "$dir/$sid" ] || return 1
  printf '%s/%s' "$dir" "$sid"
}

# suggest_seen <session_id> <name>: succeeds when the tip for the skill was already shown in the session.
suggest_seen() {
  local f
  f=$(suggest_record_file "$1") || return 1
  [ -f "$f" ] && grep -Fxq -- "$2" "$f"
}

# suggest_mark <session_id> <name>: records the tip. A failed check writes nothing.
suggest_mark() {
  local f
  f=$(suggest_record_file "$1") || return 0
  printf '%s\n' "$2" >> "$f"
}

suggest_main() {
  [ "${BF_SUGGEST_HOOK:-}" = off ] && exit 0
  prose_read_input
  local sid agent active reply transcript scan catalog prompt outcome decision name
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
  catalog=$(suggest_catalog)
  [ -n "$catalog" ] || exit 0
  prompt=$(printf '%s' "$scan" | jq -r .prompt 2>/dev/null)
  reply=$(printf '%s' "$reply" | suggest_tail "$SUGGEST_REPLY_CHARS")
  outcome=$(suggest_ask "$catalog" "$prompt" "$reply")
  case ${outcome%%$'\t'*} in
    answer) decision=$(suggest_decide "$catalog" typesafe "${outcome#*$'\t'}") ;;
    fallback) decision=$(suggest_decide "$catalog" keyword "$(suggest_fallback "$catalog" "$prompt" "$reply")") ;;
    *) exit 0 ;;
  esac
  [ -n "$decision" ] || exit 0
  if [ "$(printf '%s' "$decision" | jq -r .due)" = true ]; then
    name=$(printf '%s' "$decision" | jq -r .skill)
    if ! suggest_seen "$sid" "$name"; then
      decision=$(printf '%s' "$decision" | jq -c '.shown = true')
      suggest_tip "$decision"
      suggest_mark "$sid" "$name"
    fi
  fi
  exit 0
}

# Run only when executed. A smoke case sources the file to call one function.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then suggest_main; fi
