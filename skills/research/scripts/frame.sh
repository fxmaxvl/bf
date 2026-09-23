#!/usr/bin/env bash
# frame.sh — Judge what a standalone /bf:research prompt already answers, so
# Phase 0 asks only what is missing and Phase 3 knows its channels.
# Usage: bash frame.sh <<'BF_PROMPT'
#        <the user's research prompt>
#        BF_PROMPT
# The prompt arrives on stdin, never as an argument -- see autopilot/scripts/route.sh.
# Outputs one JSON object. Without TypeSafe (off, no key, unreachable):
#   {"boosted":false}
# and the skill runs Phase 0 and Phase 3 exactly as written. With it:
#   {"boosted":true,
#    "usecase_evident":true, "issue_evident":false,
#    "lens":"comparison", "lens_confidence":0.91, "lens_confident":true,
#    "channels":["web_docs","repo_stats"]}
# lens is null when the judgment is too weak even to recommend one. channels is
# at most two, ranked; empty means no channel cleared the bar.

set -uo pipefail

PROMPT=$(cat)
EVIDENT=0.85      # skipping a question removes the user's say: high bar
LENS_SKIP=0.85    # the same bar to skip the lens question outright
LENS_SUGGEST=0.5  # below this, do not even offer a recommendation
CHANNEL=0.5

off() { echo '{"boosted":false}'; exit 0; }
[[ -n "${PROMPT// /}" ]] || off
command -v jq >/dev/null 2>&1 || off

TS_ASK="${TYPESAFE_ASK:-$(dirname "$0")/../../typesafe/scripts/typesafe-ask.sh}"
Q=$(mktemp) || off
S=$(mktemp) || { rm -f "$Q"; off; }
trap 'rm -f "$Q" "$S"' EXIT

# One request, every question at once (speculative fan-out): the channel nouls
# are only read when the lens is decision support, but asking them costs nothing.
cat >"$Q" <<'JSON'
{"usecase_evident": {"type": "noul",
  "instructions": "Does this research request state what the person is trying to build or decide -- the goal the research serves, not just the topic?"},
 "issue_evident": {"type": "noul",
  "instructions": "Does this research request state a specific problem or question to investigate, concrete enough to know when it has been answered?"},
 "lens": {"type": "choice",
  "instructions": "Which kind of research does this request ask for?",
  "criteria": {
    "external": "prior art: how other projects, products or open-source code solve this",
    "internal": "how this codebase already handles it: reading local code and history",
    "comparison": "choosing between named or unnamed libraries, tools or services that fit a need",
    "decision": "pros and cons for a specific choice the person is about to make"}},
 "ch_code_search": {"type": "noul",
  "instructions": "Would searching public GitHub repositories and code for examples help answer this request?"},
 "ch_local_code": {"type": "noul",
  "instructions": "Would reading the local codebase and its git history help answer this request?"},
 "ch_web_docs": {"type": "noul",
  "instructions": "Would reading official documentation, changelogs or articles on the web help answer this request?"},
 "ch_repo_stats": {"type": "noul",
  "instructions": "Would repository health signals -- stars, release cadence, open issues, maintenance activity -- help answer this request?"}}
JSON
printf '%s' "$PROMPT" >"$S"

ANSWER=$(bash "$TS_ASK" --questions "$Q" --state "$S" --timeout 8 2>/dev/null) || off
printf '%s' "$ANSWER" | jq -c \
    --argjson ev "$EVIDENT" --argjson skip "$LENS_SKIP" \
    --argjson sug "$LENS_SUGGEST" --argjson ch "$CHANNEL" '
  def p($k): (.[$k].noul // 0);
  (.lens.confidence // 0) as $lc
  | ((.lens.choice // "") | IN("external","internal","comparison","decision")) as $valid
  | {boosted: true,
     usecase_evident: (p("usecase_evident") >= $ev),
     issue_evident:   (p("issue_evident") >= $ev),
     lens:            (if $valid and $lc >= $sug then .lens.choice else null end),
     lens_confidence: (if $valid then $lc else null end),
     lens_confident:  ($valid and $lc >= $skip),
     channels: ( [ to_entries[] | select(.key | startswith("ch_"))
                   | {name: (.key | ltrimstr("ch_")), p: (.value.noul // 0)}
                   | select(.p >= $ch) ]
                 | sort_by(-.p) | .[:2] | map(.name) ) }' 2>/dev/null || off
