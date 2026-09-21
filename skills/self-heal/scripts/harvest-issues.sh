#!/usr/bin/env bash
# Harvest open issues from a GitHub repo and segment each one into discrete items.
#
# Issues in this plugin are batches: one issue holds 3-4 unrelated suggestions.
# Selection and attribution both operate on items, so segmentation happens here
# once, deterministically, instead of being re-derived by the model per run.
#
# Usage: harvest-issues.sh [--repo owner/repo] [--limit N] [--brief] [--item <issue>:<index>]... [--settled]
#   --repo    default: origin of the current repo
#   --limit   max issues to fetch (default 50)
#   --brief   truncate item bodies to 320 chars (scoring pass -- cheap)
#   --item    emit only these items, untruncated (fix pass); repeatable
#   --settled also emit settled_audit_ids[]: audit-id fingerprints from issues
#             closed as not-planned. A finding closed as won't-fix is settled,
#             and without this it re-files on every subsequent audit. Costs one
#             extra gh call, so heal's scoring pass leaves it off.
#
# Output (stdout, single JSON object):
#   {repo, counts:{issues,items,emitted}, items[], notes[], settled_audit_ids?[]}
#     items[] = {id, issue, item_index, issue_title, title, url, labels[], body, chars, truncated}
#       id: "<issue>:<item_index>", e.g. "34:3" -- the handle used everywhere downstream
# Errors: {"error":"<code>","detail":"..."} + exit 1
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }

command -v gh >/dev/null 2>&1 || die gh_missing "gh CLI not installed"
command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"
gh auth status >/dev/null 2>&1 || die gh_unauthenticated "run: gh auth login"

REPO=""
LIMIT=50
BRIEF=false
SETTLED=false
WANT=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  REPO="${2:-}"; shift 2 || die bad_args "--repo needs a value" ;;
    --limit) LIMIT="${2:-}"; shift 2 || die bad_args "--limit needs a value" ;;
    --brief) BRIEF=true; shift ;;
    --item)  WANT+=("${2:-}"); shift 2 || die bad_args "--item needs <issue>:<index>" ;;
    --settled) SETTLED=true; shift ;;
    *) die bad_args "unknown argument: $1" ;;
  esac
done

if [ -z "$REPO" ]; then
  ORIGIN=$(git remote get-url origin 2>/dev/null) || die no_remote "not a git repo, or no 'origin' remote; pass --repo"
  REPO=$(printf '%s' "$ORIGIN" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')
  [ -n "$REPO" ] || die no_remote "could not parse owner/repo from: $ORIGIN"
fi

# Fingerprints of findings that were filed, considered, and closed as not-planned.
# "Settled as won't-fix" is a verdict the open-issues-only scan cannot express.
SETTLED_IDS='[]'
if [ "$SETTLED" = true ]; then
  CLOSED=$(gh issue list --repo "$REPO" --state closed --limit "$LIMIT" \
             --json body,stateReason 2>&1) \
    || die gh_failed "$(printf '%s' "$CLOSED" | head -3 | tr '\n' ' ')"
  SETTLED_IDS=$(printf '%s' "$CLOSED" | jq -c '
    [ .[] | select(.stateReason == "NOT_PLANNED") | .body // ""
      | [ scan("audit-id: *([^\n`]+)") | .[0] | gsub("^\\s+|\\s+$"; "") ] ]
    | add // [] | unique') \
    || die jq_failed "could not extract audit-ids from closed issues"
fi

RAW=$(gh issue list --repo "$REPO" --state open --limit "$LIMIT" \
        --json number,title,body,labels,url 2>&1) \
  || die gh_failed "$(printf '%s' "$RAW" | head -3 | tr '\n' ' ')"

# Segmentation runs in three stages so the optional TypeSafe pass lands *before*
# ids are handed out: `--item 34:3` in the fix pass must point at the same text
# the scoring pass scored, and it cannot if the two passes segment differently.
#   A  split every body into chunks and build items (deterministic, always runs)
#   B  optional TypeSafe re-split of bodies stage A could not divide -- a no-op
#      without a key, so the final output is unchanged for anyone who has not
#      opted in (see /bf:typesafe)
#   C  apply --item/--brief, count, annotate
STAGE_A=$(printf '%s' "$RAW" | jq -c '
  # Two delimiter formats appear in the wild: "### heading" sections and
  # "- **bold lead**" bullets. jq anchors ^ to string start, so split on a
  # newline lookahead and keep only chunks that open with the delimiter --
  # that drops any preamble prose without swallowing later items.
  def segment:
    . as $orig
    | ("\n" + .) as $b
    | (if ($b | test("\n### ")) then "### "
       elif ($b | test("\n- \\*\\*")) then "- \\*\\*"
       else null end) as $d
    | if $d == null then [$orig]
      else ( [ $b | splits("\n(?=" + $d + ")") ]
             | map(gsub("^\\s+|\\s+$"; ""))
             | map(select(length > 0 and test("^" + $d))) )
           | if length == 0 then [$orig] else . end
      end;

  def headline: split("\n")[0]
    | gsub("^### |^- "; "") | gsub("\\*\\*"; "") | gsub("^\\s+|\\s+$"; "")
    | if length > 90 then .[0:87] + "..." else . end;

  [ .[] | . as $i
    | (($i.body // "") | segment)
    | to_entries[]
    | { id: "\($i.number):\(.key + 1)", issue: $i.number, item_index: (.key + 1),
        issue_title: $i.title, title: (.value | headline), url: $i.url,
        labels: [$i.labels[].name], full: (.value | gsub("^\\s+|\\s+$"; "")) } ]
') || die jq_failed "could not build items from the issue list"

BOOSTED=$(printf '%s' "$STAGE_A" | python3 "$(dirname "$0")/boost-segments.py") || BOOSTED=""
[ -n "$BOOSTED" ] || BOOSTED="$STAGE_A"

printf '%s' "$BOOSTED" | jq -c \
  --arg repo "$REPO" --argjson brief "$BRIEF" --argjson settled "$SETTLED" \
  --argjson settled_ids "$SETTLED_IDS" --argjson want "$(printf '%s\n' "${WANT[@]+"${WANT[@]}"}" | jq -R . | jq -sc 'map(select(length>0))')" '
  . as $all
  | (if ($want | length) > 0 then [$all[] | select(.id as $id | $want | index($id))] else $all end)
  | [ .[] | . + { chars: (.full | length) }
      | . + (if $brief and (.chars > 320)
             then { body: (.full[0:320] + " ..."), truncated: true }
             else { body: .full, truncated: false } end)
      | del(.full) ]
  | { repo: $repo,
      counts: { issues: ($all | map(.issue) | unique | length),
                items: ($all | length), emitted: length },
      items: .,
      notes: ( (if $brief then ["bodies truncated to 320 chars; re-run with --item <id> for the full text"] else [] end)
             + (if ($want | length) > 0
                then [ ($want - ([.[] | .id])) | if length > 0 then "requested ids not found: \(join(", "))" else empty end ]
                else [] end) ) }
  | if $settled then . + { settled_audit_ids: $settled_ids } else . end
'
