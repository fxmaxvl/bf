#!/usr/bin/env bash
# route.sh — Resolve which bf workflow /bf:autopilot should run.
# Usage: bash route.sh <<'BF_ARGS'
#        <$ARGUMENTS>
#        BF_ARGS
# Input arrives on stdin, never as an argument: it is user text substituted into
# the command, and a backtick or " in it would be run by the shell.
# Outputs one JSON object:
#   {"target_skill":"quick","target_args":"fix login bug","routed_by":"exact","confidence":null}
# routed_by: exact    -- first word named a skill; no judgment was asked
#            typesafe -- TypeSafe picked the skill from the whole input
#            default  -- no exact match and no confident judgment: feature, as always

set -uo pipefail

ARGS=$(cat)
KNOWN="feature quick micro review design"

emit() {
    jq -cn --arg s "$1" --arg a "$2" --arg by "$3" --argjson c "${4:-null}" \
        '{target_skill: $s, target_args: $a, routed_by: $by, confidence: $c}'
}

# Parameter expansion rather than `read`, which would drop every line after the
# first of a multi-line argument.
TRIMMED="${ARGS#"${ARGS%%[![:space:]]*}"}"
FIRST="${TRIMMED%%[[:space:]]*}"
REST="${TRIMMED#"$FIRST"}"
REST="${REST#"${REST%%[![:space:]]*}"}"
for s in $KNOWN; do
    if [[ "${FIRST:-}" == "$s" ]]; then
        emit "$s" "${REST:-}" exact
        exit 0
    fi
done

# No skill named. Deterministic behaviour is feature with the whole input --
# the safe superset, since every other workflow skips phases feature runs.
# When TypeSafe is on, route by intent instead, so "fix the login bug" does not
# pay for a brainstorm. A pick that skips phases needs a high bar; below it,
# or on any unavailability, feature stands.
CONFIDENT_ROUTE=0.8
if [[ -n "${ARGS// /}" ]]; then
    TS_ASK="${TYPESAFE_ASK:-$(dirname "$0")/../../typesafe/scripts/typesafe-ask.sh}"
    Q=$(mktemp); S=$(mktemp)
    cat >"$Q" <<'JSON'
{"workflow": {"type": "choice",
  "instructions": "A developer handed this request to an autonomous coding agent. Which workflow fits the work it describes?",
  "criteria": {
    "feature": "a new capability or substantial change whose shape is still open: needs brainstorming, a spec and a design before planning and implementation",
    "quick": "a well-understood change such as a bug fix or a small feature: the goal is clear, so it can go straight to research, plan, implement and verify",
    "micro": "a small, focused refactor or mechanical edit (rename, move, extract, tidy) with no new behaviour",
    "review": "review existing code, a pull request, a branch or a commit range; nothing new is to be written",
    "design": "produce a system-design document with diagrams for an idea; no code, no branch, no pull request"}}}
JSON
    printf '%s' "$ARGS" >"$S"
    ANSWER=$(bash "$TS_ASK" --questions "$Q" --state "$S" --timeout 8 2>/dev/null) || ANSWER=""
    rm -f "$Q" "$S"
    if [[ -n "$ANSWER" ]]; then
        PICK=$(printf '%s' "$ANSWER" | jq -r --argjson bar "$CONFIDENT_ROUTE" --arg known "$KNOWN" '
          .workflow // {} |
          if ((.choice // "") as $c | $known | split(" ") | index($c)) and (.confidence // 0) >= $bar
          then "\(.choice) \(.confidence)" else "" end' 2>/dev/null)
        if [[ -n "$PICK" ]]; then
            emit "${PICK% *}" "$ARGS" typesafe "${PICK#* }"
            exit 0
        fi
    fi
fi

emit feature "$ARGS" default
