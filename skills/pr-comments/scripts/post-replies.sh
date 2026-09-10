#!/usr/bin/env bash
# Post the approved replies and resolve the threads they answer.
#
# Usage: post-replies.sh <plan.json> [<pr-number> | <pr-url>] [--dry-run]
#
# plan.json is a JSON array; one entry per comment being answered:
#   [{"kind":"thread","thread_id":"PRRT_...","reply":"...","resolve":true},
#    {"kind":"issue","reply":"..."},
#    {"kind":"thread","thread_id":"PRRT_...","resolve":true}]
#   "reply" may be omitted (resolve only); "resolve" defaults to false.
#   "issue"/"review" entries have no thread — they post as a PR-level comment
#   and cannot be resolved.
#
# Output: {"posted":N,"resolved":N,"skipped":N,"results":[...]}
# Each result: {index, kind, reply: ok|skipped|failed, resolve: ok|skipped|failed, detail}
# Exit 0 when every action succeeded, 1 when any failed (results say which).
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }

command -v gh >/dev/null 2>&1 || die gh_missing "gh CLI not installed"
command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"
gh auth status >/dev/null 2>&1 || die gh_unauthenticated "run: gh auth login"

PLAN=""; ARG=""; DRY=false
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=true ;;
    ""|--*) ;;
    *) if [[ -z "$PLAN" ]]; then PLAN="$a"; else ARG="$a"; fi ;;
  esac
done

[[ -n "$PLAN" && -f "$PLAN" ]] || die no_plan "plan file not found: ${PLAN:-<missing>}"
jq -e 'type == "array"' "$PLAN" >/dev/null 2>&1 || die bad_plan "plan must be a JSON array"

if [[ "$ARG" =~ ^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; NUM="${BASH_REMATCH[3]}"
else
  NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || die no_repo "not a GitHub repo"
  OWNER="${NWO%%/*}"; REPO="${NWO##*/}"
  if [[ "$ARG" =~ ^#?([0-9]+)$ ]]; then NUM="${BASH_REMATCH[1]}"
  else NUM=$(gh pr view --json number -q .number 2>/dev/null) || die no_pr "no PR for the current branch"; fi
fi

POSTED=0; RESOLVED=0; SKIPPED=0; FAILED=0
RESULTS=$(mktemp); printf '[]' > "$RESULTS"

record() { # index kind reply_status resolve_status detail
  jq --argjson i "$1" --arg k "$2" --arg r "$3" --arg s "$4" --arg d "$5" \
     '. + [{index:$i, kind:$k, reply:$r, resolve:$s, detail:$d}]' "$RESULTS" > "$RESULTS.tmp" \
     && mv "$RESULTS.tmp" "$RESULTS"
}

COUNT=$(jq 'length' "$PLAN")
for ((i=0; i<COUNT; i++)); do
  KIND=$(jq -r ".[$i].kind // \"thread\"" "$PLAN")
  TID=$(jq -r ".[$i].thread_id // empty" "$PLAN")
  BODY=$(jq -r ".[$i].reply // empty" "$PLAN")
  WANT_RESOLVE=$(jq -r ".[$i].resolve // false" "$PLAN")
  RSTAT="skipped"; SSTAT="skipped"; DETAIL=""

  if [[ "$DRY" == true ]]; then
    [[ -n "$BODY" ]] && RSTAT="dry-run"
    if [[ "$WANT_RESOLVE" == true ]]; then
      if [[ "$KIND" == "thread" && -n "$TID" ]]; then SSTAT="dry-run"
      else DETAIL="$KIND comments have no thread to resolve"; fi
    fi
    record "$i" "$KIND" "$RSTAT" "$SSTAT" "${DETAIL:+$DETAIL; }not sent (--dry-run)"; continue
  fi

  if [[ -n "$BODY" ]]; then
    if [[ "$KIND" == "thread" ]]; then
      [[ -n "$TID" ]] || { RSTAT="failed"; DETAIL="thread entry has no thread_id"; }
      if [[ "$RSTAT" != "failed" ]]; then
        if OUT=$(gh api graphql -F tid="$TID" -F body="$BODY" -f query='
          mutation($tid:ID!,$body:String!){
            addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$tid, body:$body}){
              comment{url}}}' 2>&1); then
          RSTAT="ok"; POSTED=$((POSTED+1))
          DETAIL=$(printf '%s' "$OUT" | jq -r '.data.addPullRequestReviewThreadReply.comment.url // empty')
        else
          RSTAT="failed"; FAILED=$((FAILED+1))
          DETAIL=$(printf '%s' "$OUT" | tr -d '\n' | head -c 300)
        fi
      else
        FAILED=$((FAILED+1))
      fi
    else
      if OUT=$(gh api "repos/$OWNER/$REPO/issues/$NUM/comments" -f body="$BODY" 2>&1); then
        RSTAT="ok"; POSTED=$((POSTED+1))
        DETAIL=$(printf '%s' "$OUT" | jq -r '.html_url // empty' 2>/dev/null)
      else
        RSTAT="failed"; FAILED=$((FAILED+1))
        DETAIL=$(printf '%s' "$OUT" | tr -d '\n' | head -c 300)
      fi
    fi
  fi

  if [[ "$WANT_RESOLVE" == true ]]; then
    if [[ "$KIND" != "thread" || -z "$TID" ]]; then
      SSTAT="skipped"
      DETAIL="${DETAIL:+$DETAIL; }$KIND comments have no thread to resolve"
    elif OUT=$(gh api graphql -F tid="$TID" -f query='
        mutation($tid:ID!){ resolveReviewThread(input:{threadId:$tid}){ thread{isResolved} } }' 2>&1); then
      SSTAT="ok"; RESOLVED=$((RESOLVED+1))
    else
      SSTAT="failed"; FAILED=$((FAILED+1))
      DETAIL="${DETAIL:+$DETAIL; }$(printf '%s' "$OUT" | tr -d '\n' | head -c 300)"
    fi
  fi

  [[ "$RSTAT" == "skipped" && "$SSTAT" == "skipped" ]] && SKIPPED=$((SKIPPED+1))
  record "$i" "$KIND" "$RSTAT" "$SSTAT" "$DETAIL"
done

jq -n --argjson p "$POSTED" --argjson r "$RESOLVED" --argjson s "$SKIPPED" \
      --argjson f "$FAILED" --argjson res "$(cat "$RESULTS")" \
      '{posted:$p, resolved:$r, skipped:$s, failed:$f, results:$res}'
rm -f "$RESULTS"
[[ "$FAILED" -eq 0 ]]
