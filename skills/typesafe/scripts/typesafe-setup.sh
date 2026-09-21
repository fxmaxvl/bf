#!/usr/bin/env bash
# Turn TypeSafe boosting on or off in ~/.bf/config.json, and prove the key works.
#
# Usage: typesafe-setup.sh <status|on|off> [--key-env <VAR>] [--model <name>]
#   status  report resolved state; makes a live smoke call only if enabled
#   on      smoke-call the API first, and write the flag only if it answers
#   off     set enabled:false, leaving every other key in the config untouched
#   --key-env  env var holding the key (default TYPESAFE_API_KEY). The key is
#              never written to disk and never printed.
#
# Output (stdout, single JSON object):
#   {action, enabled, api_key_env, key_present, model, config, smoke:{ran,ok,detail}}
# Errors: {"error":"<code>","detail":"..."} + exit 1
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }

command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"

ACTION="${1:-status}"; shift || true
KEY_ENV=""
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key-env) KEY_ENV="${2:-}"; shift 2 || die bad_args "--key-env needs a value" ;;
    --model)   MODEL="${2:-}"; shift 2 || die bad_args "--model needs a value" ;;
    *) die bad_args "unknown argument: $1" ;;
  esac
done
case "$ACTION" in status|on|off) ;; *) die bad_args "action must be status, on or off" ;; esac

CONFIG="$HOME/.bf/config.json"
[ -f "$CONFIG" ] && ! jq -e . "$CONFIG" >/dev/null 2>&1 \
  && die config_malformed "$CONFIG is not valid JSON -- fix or move it before enabling"

# Existing values win over defaults, so `on` after a custom `--key-env` keeps it.
CUR_ENV=$(jq -r '.typesafe.api_key_env // empty' "$CONFIG" 2>/dev/null || true)
CUR_MODEL=$(jq -r '.typesafe.model // empty' "$CONFIG" 2>/dev/null || true)
KEY_ENV="${KEY_ENV:-${CUR_ENV:-TYPESAFE_API_KEY}}"
MODEL="${MODEL:-${CUR_MODEL:-jev-latest}}"
ENABLED=$(jq -r 'try (.typesafe.enabled // false) catch false' "$CONFIG" 2>/dev/null || echo false)

KEY="${!KEY_ENV:-}"
KEY_PRESENT=$([ -n "$KEY" ] && echo true || echo false)

SMOKE_RAN=false; SMOKE_OK=false; SMOKE_DETAIL=""

# A smoke call is the whole point of the `on` path: without it a typo'd key is
# invisible, and every boosted call site silently falls back forever.
smoke() {
  SMOKE_RAN=true
  if [ "$KEY_PRESENT" != true ]; then
    SMOKE_DETAIL="\$$KEY_ENV is not set in this shell"; return
  fi
  command -v curl >/dev/null 2>&1 || { SMOKE_DETAIL="curl not installed"; return; }
  local body code
  body=$(mktemp) || { SMOKE_DETAIL="mktemp failed"; return; }
  code=$(curl -sS -o "$body" -w '%{http_code}' --max-time 20 \
    -X POST https://api.typesafe.ai/v1/systemone \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg m "$MODEL" '{state:"The deploy failed because the disk was full.",
       model:$m, questions:{is_infra:{type:"noul",
       instructions:"This message describes an infrastructure problem rather than a code defect."}}}')" \
    2>/dev/null) || { SMOKE_DETAIL="request failed or timed out"; rm -f "$body"; return; }
  case "$code" in
    2*) if jq -e '.answers.is_infra.noul' "$body" >/dev/null 2>&1; then
          SMOKE_OK=true
          SMOKE_DETAIL="answered (model $(jq -r '.model // "unknown"' "$body"))"
        else SMOKE_DETAIL="HTTP 200 but no answer in the reply"; fi ;;
    401|403) SMOKE_DETAIL="auth rejected (HTTP $code) -- the key in \$$KEY_ENV is not accepted" ;;
    429|529) SMOKE_DETAIL="rate limited (HTTP $code) -- key may be fine, try again" ;;
    *)       SMOKE_DETAIL="HTTP $code from api.typesafe.ai" ;;
  esac
  rm -f "$body"
}

write_config() { # enabled
  mkdir -p "$(dirname "$CONFIG")" || die config_unwritable "cannot create $(dirname "$CONFIG")"
  local tmp; tmp=$(mktemp) || die mktemp_failed ""
  # Merge into whatever else lives in the config -- parallel_audit and friends stay put.
  jq --argjson en "$1" --arg env "$KEY_ENV" --arg model "$MODEL" \
     '.typesafe = ((.typesafe // {}) + {enabled:$en, api_key_env:$env, model:$model})' \
     "$CONFIG" 2>/dev/null >"$tmp" \
    || jq -n --argjson en "$1" --arg env "$KEY_ENV" --arg model "$MODEL" \
         '{typesafe:{enabled:$en, api_key_env:$env, model:$model}}' >"$tmp" \
    || { rm -f "$tmp"; die config_unwritable "could not build new config"; }
  mv "$tmp" "$CONFIG" || { rm -f "$tmp"; die config_unwritable "could not write $CONFIG"; }
  ENABLED="$1"
}

case "$ACTION" in
  status) [ "$ENABLED" = true ] && smoke ;;
  on)     smoke; [ "$SMOKE_OK" = true ] && write_config true ;;
  off)    [ -f "$CONFIG" ] && write_config false || ENABLED=false ;;
esac

jq -nc --arg a "$ACTION" --argjson en "${ENABLED:-false}" --arg env "$KEY_ENV" \
   --argjson kp "$KEY_PRESENT" --arg model "$MODEL" --arg cfg "$CONFIG" \
   --argjson sr "$SMOKE_RAN" --argjson so "$SMOKE_OK" --arg sd "$SMOKE_DETAIL" \
   '{action:$a, enabled:$en, api_key_env:$env, key_present:$kp, model:$model,
     config:$cfg, smoke:{ran:$sr, ok:$so, detail:$sd}}'
