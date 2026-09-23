#!/usr/bin/env bash
# tag-citations.sh — Check each research citation's evidence type against what
# its quote actually shows, instead of the writer grading its own evidence.
# Usage: bash tag-citations.sh <<'JSON'
#          [{"claim": "...", "source": "...", "locator": "...",
#            "quote_or_summary": "...", "evidence_type": "direct|inference|doc"}, ...]
#        JSON
# Outputs the same array, each entry gaining:
#   "judged_type": direct|inference|doc|unsupported|null, "judged_confidence": 0..1|null
# evidence_type is overwritten only by a confident direct/inference/doc judgment.
# unsupported is never applied -- it is reported for the skill to act on. Without
# TypeSafe, the input comes back unchanged apart from the two null fields.

set -uo pipefail

CONFIDENT_TAG=0.8

IN=$(cat)
command -v jq >/dev/null 2>&1 || { printf '%s\n' "$IN"; exit 0; }
printf '%s' "$IN" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "tag-citations.sh: stdin must be a JSON array" >&2; exit 2; }

unchanged() { printf '%s' "$IN" | jq -c 'map(. + {judged_type: null, judged_confidence: null})'; exit 0; }
[[ $(printf '%s' "$IN" | jq 'length') -gt 0 ]] || unchanged

TS_ASK="${TYPESAFE_ASK:-$(dirname "$0")/../../typesafe/scripts/typesafe-ask.sh}"
Q=$(mktemp) || unchanged
S=$(mktemp) || { rm -f "$Q"; unchanged; }
trap 'rm -f "$Q" "$S"' EXIT

printf '%s' "$IN" | jq -c '
  to_entries | map({ key: "c\(.key)", value: { type: "choice",
    instructions: "Citation \(.key) in `citations` backs its `claim` with `quote_or_summary` taken from `source`. What kind of evidence is it for that claim?",
    criteria: {
      direct: "primary evidence that shows the claim itself: code, data, test output, observed behaviour, or a maintainer stating a fact about their own project",
      doc: "documentation, a README, a blog post or marketing copy asserting the claim, without showing it",
      inference: "the claim is reasoned from the evidence; the quote supports it but does not state or show it",
      unsupported: "the quote does not support the claim, or contradicts it"} } })
  | from_entries' >"$Q" 2>/dev/null || unchanged
printf '%s' "$IN" | jq -c '{citations: map({claim, source, quote_or_summary})}' >"$S" 2>/dev/null || unchanged

ANSWER=$(bash "$TS_ASK" --questions "$Q" --state "$S" --timeout 15 2>/dev/null) || unchanged
printf '%s' "$IN" | jq -c --argjson a "$ANSWER" --argjson bar "$CONFIDENT_TAG" '
  to_entries | map(
    ($a["c\(.key)"] // {}) as $j
    | (($j.choice // "") | IN("direct","doc","inference","unsupported")) as $valid
    | .value + {judged_type: (if $valid then $j.choice else null end),
                judged_confidence: (if $valid then ($j.confidence // null) else null end)}
    | if $valid and $j.choice != "unsupported" and ($j.confidence // 0) >= $bar
      then .evidence_type = $j.choice else . end )' 2>/dev/null || unchanged
