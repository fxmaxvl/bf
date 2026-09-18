#!/usr/bin/env bash
# Wait for an in-flight PR review to land, bounded by a timeout.
#
# Invoking pr-comments mid-review finds only the bot's "started reviewing" post
# and nothing actionable. Hand-rolling the wait outside the skill re-invents the
# interval, exit condition and timeout every time -- and a loop that watches only
# for findings hangs silently through a review that fails or is abandoned. This
# settles all three: findings, a review that settled without findings, or timeout.
#
# Usage: wait-for-review.sh [<pr number|url>] [--timeout <seconds>] [--interval <seconds>]
#   no pr arg  -> PR for the current branch
#   --timeout   default 600
#   --interval  default 30
#
# Output (stdout, single JSON object):
#   {status, waited_seconds, actionable, reviews_before, reviews_now, polls}
#     status: "findings"      -- actionable comments arrived; run the normal flow
#             "review_settled"-- a review completed but produced nothing actionable
#             "timeout"       -- neither happened in time; the review may have failed
# Exit code is 0 for all three; the caller decides. Errors: {"error":...} + exit 1
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }
command -v gh >/dev/null 2>&1 || die gh_missing "gh CLI not installed"
command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FETCH="$HERE/fetch-pr-comments.sh"
[ -x "$FETCH" ] || [ -f "$FETCH" ] || die fetch_missing "fetch-pr-comments.sh not found beside this script"

PR=""; TIMEOUT=600; INTERVAL=30
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)  TIMEOUT="${2:-}"; shift 2 || die bad_args "--timeout needs a value" ;;
    --interval) INTERVAL="${2:-}"; shift 2 || die bad_args "--interval needs a value" ;;
    -*) die bad_args "unknown flag: $1" ;;
    *)  PR="$1"; shift ;;
  esac
done
case "$TIMEOUT$INTERVAL" in *[!0-9]*) die bad_args "--timeout and --interval must be integers" ;; esac
[ "$INTERVAL" -gt 0 ] || die bad_args "--interval must be greater than 0"

# A review count taken before waiting; any settled review that appears later is
# the one being waited on, whether or not it produced findings.
review_count() {
  gh pr view ${PR:+"$PR"} --json reviews \
    --jq '[.reviews[] | select(.state != "PENDING")] | length' 2>/dev/null || echo ""
}

actionable_now() {
  bash "$FETCH" ${PR:+"$PR"} 2>/dev/null | jq -r '.counts.actionable // empty' 2>/dev/null
}

BEFORE=$(review_count)
[ -n "$BEFORE" ] || die gh_failed "could not read reviews; check the PR argument and gh auth"

START=$SECONDS
POLLS=0
while :; do
  POLLS=$((POLLS+1))
  ACT=$(actionable_now)
  NOW=$(review_count)

  if [ -n "$ACT" ] && [ "$ACT" -gt 0 ] 2>/dev/null; then
    STATUS=findings; break
  fi
  if [ -n "$NOW" ] && [ -n "$BEFORE" ] && [ "$NOW" -gt "$BEFORE" ] 2>/dev/null; then
    STATUS=review_settled; break
  fi
  if [ $((SECONDS - START)) -ge "$TIMEOUT" ]; then
    STATUS=timeout; break
  fi
  sleep "$INTERVAL"
done

jq -cn --arg s "$STATUS" --argjson w "$((SECONDS - START))" \
  --arg a "${ACT:-}" --argjson b "${BEFORE:-0}" --arg n "${NOW:-}" --argjson p "$POLLS" \
  '{status:$s, waited_seconds:$w,
    actionable:(if $a=="" then null else ($a|tonumber) end),
    reviews_before:$b,
    reviews_now:(if $n=="" then null else ($n|tonumber) end),
    polls:$p}'
