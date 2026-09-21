#!/usr/bin/env bash
# Ask TypeSafe (System One / Jev) a set of typed questions. The one entry point
# every boosted call site uses.
#
# TypeSafe is opt-in boosting, never a dependency: when it is off, unconfigured,
# or unreachable, this exits 3 and prints nothing on stdout. The caller does not
# learn why -- it just runs the deterministic path it would have run anyway.
#
# Usage: typesafe-ask.sh --questions <file.json> [--state <file>] [--timeout <secs>]
#   --questions  JSON object of {id: {type, instructions, criteria}} -- see
#                https://docs.typesafe.ai/api.md
#   --state      file holding the JSON value to judge (object, array or string).
#                A bare string file is sent as a JSON string. Default: null.
#   --timeout    hard wall-clock cap, default 20s. /bf:autopilot runs unattended;
#                a hung request must never stall it.
#
# Output (stdout, on success only): the `answers` object, e.g.
#   {"verdict":{"type":"choice","choice":"block","confidence":0.91,"probabilities":{...}}}
# Exit codes:
#   0  answers on stdout
#   2  bad usage (caller bug -- not a fallback condition)
#   3  unavailable: disabled, no key, non-2xx, timeout, or malformed reply.
#      Reason goes to stderr. THIS IS THE FALLBACK SIGNAL.
set -uo pipefail

CONFIG="$HOME/.bf/config.json"
TIMEOUT=20
QFILE=""
SFILE=""

usage() { echo "usage: typesafe-ask.sh --questions <file.json> [--state <file>] [--timeout <secs>]" >&2; exit 2; }
off()   { echo "typesafe: $1" >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --questions) QFILE="${2:-}"; shift 2 || usage ;;
    --state)     SFILE="${2:-}"; shift 2 || usage ;;
    --timeout)   TIMEOUT="${2:-}"; shift 2 || usage ;;
    *) usage ;;
  esac
done
[ -n "$QFILE" ] && [ -f "$QFILE" ] || usage

command -v jq   >/dev/null 2>&1 || off "jq not installed"
command -v curl >/dev/null 2>&1 || off "curl not installed"

# ---- resolve opt-in ---------------------------------------------------------
# Absent, malformed or disabled config all mean the same thing: not boosted.
[ -f "$CONFIG" ] || off "not configured (run /bf:typesafe)"
ENABLED=$(jq -r 'try (.typesafe.enabled // false) catch false' "$CONFIG" 2>/dev/null) || off "config unreadable"
[ "$ENABLED" = "true" ] || off "disabled in $CONFIG"

KEY_ENV=$(jq -r '.typesafe.api_key_env // "TYPESAFE_API_KEY"' "$CONFIG" 2>/dev/null)
KEY="${!KEY_ENV:-}"
[ -n "$KEY" ] || off "\$$KEY_ENV is empty in this shell"

MODEL=$(jq -r '.typesafe.model // "jev-latest"' "$CONFIG" 2>/dev/null)

# ---- build request ----------------------------------------------------------
jq -e . "$QFILE" >/dev/null 2>&1 || off "--questions is not valid JSON"

if [ -n "$SFILE" ]; then
  [ -f "$SFILE" ] || off "--state file not found: $SFILE"
  # A state file is usually JSON, but a plain-text dump is legitimate state too:
  # send it as a JSON string rather than making every caller pre-encode it.
  if jq -e . "$SFILE" >/dev/null 2>&1; then
    STATE_ARG=(--slurpfile st "$SFILE")
    STATE_EXPR='$st[0]'
  else
    STATE_ARG=(--rawfile st "$SFILE")
    STATE_EXPR='$st'
  fi
else
  STATE_ARG=(--null-input)
  STATE_EXPR='null'
fi

REQ=$(mktemp) || off "mktemp failed"
BODY=$(mktemp) || { rm -f "$REQ"; off "mktemp failed"; }
trap 'rm -f "$REQ" "$BODY"' EXIT

jq -n "${STATE_ARG[@]}" --slurpfile q "$QFILE" --arg model "$MODEL" \
  "{state: $STATE_EXPR, model: \$model, questions: \$q[0]}" >"$REQ" 2>/dev/null \
  || off "could not build request body"

# ---- call -------------------------------------------------------------------
CODE=$(curl -sS -o "$BODY" -w '%{http_code}' \
  --max-time "$TIMEOUT" \
  -X POST https://api.typesafe.ai/v1/systemone \
  -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  --data-binary "@$REQ" 2>/dev/null) || off "request failed or timed out after ${TIMEOUT}s"

case "$CODE" in
  2*) ;;
  401|403) off "auth rejected (HTTP $CODE) -- check \$$KEY_ENV" ;;
  429|529) off "rate limited (HTTP $CODE)" ;;
  *)  off "HTTP $CODE from api.typesafe.ai" ;;
esac

jq -e '.answers' "$BODY" >/dev/null 2>&1 || off "reply carried no answers"
jq -c '.answers' "$BODY"
