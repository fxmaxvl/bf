#!/usr/bin/env bash
# Verify a bf:essence ledger accounts for every candidate: each lands in exactly one bucket,
# nothing is cut without a reason, and the vital few fit the budget.
#
# Usage: ledger-check.sh <ledger.json>
# Ledger shape:
#   {"budget": 3, "intent": "...", "candidates": [
#     {"id":"C1","claim":"...","locator":"## Goals","bucket":"vital"},
#     {"id":"C2","claim":"...","locator":"## Security","bucket":"non_negotiable"},
#     {"id":"C3","claim":"...","locator":"## Ideas","bucket":"parked","reason":"..."},
#     {"id":"C4","claim":"...","locator":"## Goals","bucket":"merged","into":"C1"}]}
# Rules: candidates is a non-empty array of objects; id, claim and locator are non-empty strings
# and ids are unique; bucket is vital, non_negotiable, parked or merged; parked needs a reason;
# merged needs `into` naming a vital candidate; budget is an integer >= 1; intent is a non-empty
# string; vital count <= budget; at least one vital unless every candidate is non_negotiable.
# This checks accounting only. Whether a merged claim survives in its target's wording is the
# model's check, not this script's.
#
# Output: {"ok":bool,"counts":{vital,non_negotiable,parked,merged,total},"errors":[...]}
#   exit 0 when ok, 1 when not. Wrong types become errors entries, never a crash.
#   {"error":"no_jq"|"not_found"|"bad_json"|"bad_ledger","detail":...} + exit 1 when the ledger
#   cannot be checked at all.
set -uo pipefail

command -v jq >/dev/null || { printf '{"error":"no_jq","detail":"jq is required"}\n'; exit 1; }
die() { jq -cn --arg e "$1" --arg d "$2" '{error:$e,detail:$d}'; exit 1; }
[ -f "${1-}" ] || die not_found "ledger file: ${1-<none>}"
jq -e 'type == "object"' "$1" >/dev/null 2>&1 || die bad_json "$1 is not a JSON object"

result=$(jq '
  def str: type == "string" and length > 0;
  def buckets: ["vital","non_negotiable","parked","merged"];
  (.candidates) as $raw
  | (if ($raw | type) == "array" then $raw else [] end) as $arr
  | ($arr | map(select(type == "object"))) as $c
  | ($c | map(select(.bucket == "vital"))) as $vital
  | ($vital | map(.id | select(str))) as $vital_ids
  | def n(b): [$c[] | select(.bucket == b)] | length;
    {vital: n("vital"), non_negotiable: n("non_negotiable"), parked: n("parked"),
     merged: n("merged"), total: ($c | length)} as $counts
  | (.budget | type == "number" and . >= 1 and . == floor) as $budget_ok
  | [
    (if ($raw | type) != "array" or ($raw | length) == 0 then "candidates must be a non-empty array" else empty end),
    ($arr | to_entries[] | select(.value | type != "object") | "candidate #\(.key + 1) is not an object"),
    ($arr | to_entries[] | select(.value | type == "object")
      | .value as $x
      | (if ($x.id | str) then $x.id else "candidate #\(.key + 1)" end) as $l
      | (if ($x.id | str | not) then "\($l): id must be a non-empty string" else empty end),
        (if ($x.claim | str | not) then "\($l): claim must be a non-empty string" else empty end),
        (if ($x.locator | str | not) then "\($l): no source locator" else empty end),
        (if ($x.bucket | type) != "string" or (buckets | index($x.bucket)) == null
         then "\($l): bucket must be vital, non_negotiable, parked or merged (got \($x.bucket | tojson))" else empty end),
        (if $x.bucket == "parked" and ($x.reason | str | not) then "\($l): parked without a reason" else empty end),
        (if $x.bucket == "merged"
         then if ($x.into | type) != "string" then "\($l): merged without an into id"
              elif ($vital_ids | index($x.into)) == null then "\($l): merged into \($x.into), which is not vital"
              else empty end
         else empty end)),
    ($c | map(.id | select(str)) | group_by(.)[] | select(length > 1) | "duplicate id \(.[0])"),
    (if $budget_ok | not then "budget must be an integer >= 1" else empty end),
    (if (.intent | str | not) then "intent must be a non-empty string" else empty end),
    (if $budget_ok and $counts.vital > .budget
     then "\($counts.vital) vital directions exceed the budget of \(.budget)" else empty end),
    (if ($raw | type) == "array" and ($raw | length) > 0 and $counts.vital == 0 and $counts.non_negotiable < $counts.total
     then "no vital direction kept" else empty end)
  ] as $errors
  | {ok: ($errors | length == 0), counts: $counts, errors: $errors}
' "$1") || die bad_ledger "jq could not evaluate $1"

printf '%s\n' "$result"
jq -e .ok <<< "$result" >/dev/null
