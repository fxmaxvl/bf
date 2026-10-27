#!/usr/bin/env bash
# Verify a bf:essence ledger accounts for every candidate: each lands in exactly one bucket,
# nothing is cut without a reason, and the vital few fit the budget.
#
# Usage: ledger-check.sh <ledger.json>
# Ledger shape:
#   {"budget": 3, "intent": "...", "candidates": [
#     {"id":"C1","claim":"...","locator":"## Goals","bucket":"vital","absorbs":["C4"]},
#     {"id":"C2","claim":"...","locator":"## Security","bucket":"non_negotiable"},
#     {"id":"C3","claim":"...","locator":"## Ideas","bucket":"parked","reason":"..."},
#     {"id":"C4","claim":"...","locator":"## Goals","bucket":"merged","into":"C1"}]}
# This checks accounting only. Whether a merged claim survives in its target's wording is the
# model's check, not this script's.
#
# Output: {"ok":bool,"counts":{vital,non_negotiable,parked,merged,total},"errors":[...]}
#   exit 0 when ok, 1 when not; {"error":...} + exit 1 when the ledger cannot be read.
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; exit 1; }
command -v jq >/dev/null || die no_jq "jq is required"
[ -f "${1-}" ] || die not_found "ledger file: ${1-<none>}"
jq -e 'type == "object"' "$1" >/dev/null 2>&1 || die bad_json "$1 is not a JSON object"

result=$(jq '
  (.candidates // []) as $c
  | ($c | map(select(.bucket == "vital"))) as $vital
  | ($vital | map(.id)) as $vital_ids
  | def nonempty(f): (f // "" | tostring | length) > 0;
  [
    (if ($c | length) == 0 then "no candidates" else empty end),
    (if (.budget | type) != "number" or .budget < 1 then "budget must be a positive integer" else empty end),
    ($c | group_by(.id)[] | select(length > 1) | "duplicate id \(.[0].id)"),
    ($c[] | select(nonempty(.id) | not) | "candidate without id: \(.claim // "?")"),
    ($c[] | select(nonempty(.claim) | not) | "\(.id): empty claim"),
    ($c[] | select(nonempty(.locator) | not) | "\(.id): no source locator"),
    ($c[] | select(.bucket as $b | ["vital","non_negotiable","parked","merged"] | index($b) | not)
          | "\(.id): bucket must be vital, non_negotiable, parked or merged (got \(.bucket // "none"))"),
    ($c[] | select(.bucket == "parked" and (nonempty(.reason) | not)) | "\(.id): parked without a reason"),
    ($c[] | select(.bucket == "merged") as $m
          | if ($vital_ids | index($m.into)) == null then "\($m.id): merged into \($m.into // "nothing"), which is not vital"
            elif ([$vital[] | select(.id == $m.into) | (.absorbs // []) | index($m.id)] | first) == null
            then "\($m.id): \($m.into) does not list it in absorbs"
            else empty end),
    ($vital[] as $v | ($v.absorbs // [])[] as $a
          | if ([$c[] | select(.id == $a and .bucket == "merged" and .into == $v.id)] | length) == 0
            then "\($v.id): absorbs \($a), which is not merged into it" else empty end),
    (if ($vital | length) == 0 and ($c | map(select(.bucket == "non_negotiable")) | length) == 0
     then "no vital direction or non-negotiable kept" else empty end),
    (if (.budget | type) == "number" and ($vital | length) > .budget
     then "\($vital | length) vital directions exceed the budget of \(.budget)" else empty end)
  ] as $errors
  | {ok: ($errors | length == 0),
     counts: {vital: ($vital | length),
              non_negotiable: ($c | map(select(.bucket == "non_negotiable")) | length),
              parked: ($c | map(select(.bucket == "parked")) | length),
              merged: ($c | map(select(.bucket == "merged")) | length),
              total: ($c | length)},
     errors: $errors}
' "$1") || die bad_ledger "jq could not evaluate $1"

printf '%s\n' "$result"
jq -e .ok <<< "$result" >/dev/null
