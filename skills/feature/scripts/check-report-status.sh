#!/usr/bin/env bash
# check-report-status.sh — Extract the STATUS line from a review or complexity report.
# Replaces the model reading an entire report file just to check one line.
# Usage: bash check-report-status.sh <report-file> [--block <header>]
# Outputs: PASS | CONCERN | BLOCK | ADVISORY | NOT_FOUND
#
# --block <header>  Extract only that block (e.g. "## Implementation Review") before checking.
#                   Required when multiple reports share a single temp file.

set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
    echo "Usage: check-report-status.sh <file> [--block <header>]" >&2
    exit 1
fi

BLOCK_HEADER=""
if [[ "${2:-}" == "--block" ]]; then
    BLOCK_HEADER="${3:-}"
    if [[ -z "$BLOCK_HEADER" ]]; then
        echo "Error: --block requires a header argument" >&2
        exit 1
    fi
fi

if [[ ! -f "$FILE" ]]; then
    echo "NOT_FOUND"
    exit 0
fi

if [[ -n "$BLOCK_HEADER" ]]; then
    # Extract the named block: from the header line to the next ^## or EOF
    CONTENT=$(bash "$(dirname "$0")/read-block.sh" "$FILE" --block "$BLOCK_HEADER")
else
    CONTENT=$(cat "$FILE")
fi

STATUS=$(echo "$CONTENT" | grep -m1 -E '^STATUS:' 2>/dev/null | sed 's/^STATUS:[[:space:]]*//' | tr -d '[:space:]' || true)

# The grep is the fast path and stays authoritative. It only misses when the
# report drifted from the agreed line format (`**STATUS:** BLOCK`, or a verdict
# stated in a sentence) -- and a miss reads as NOT_FOUND, which callers cannot
# tell apart from "no report", so a gate silently opens. When TypeSafe is on,
# read the verdict out of the prose instead; when it is not, or the answer is
# not confident, fall through to NOT_FOUND exactly as before.
CONFIDENT_VERDICT=0.8
if [[ -z "$STATUS" && -n "${CONTENT// /}" ]]; then
    TS_ASK="${TYPESAFE_ASK:-$(dirname "$0")/../../typesafe/scripts/typesafe-ask.sh}"
    Q=$(mktemp); S=$(mktemp)
    cat >"$Q" <<'JSON'
{"verdict": {"type": "choice",
  "instructions": "This is a review report written by another agent. What verdict does it reach overall?",
  "criteria": {
    "pass": "no problems worth acting on; the work can proceed as it stands",
    "concern": "problems worth raising, but none that must be fixed before proceeding",
    "block": "at least one problem that must be fixed before the work proceeds",
    "advisory": "observations offered for consideration; the report does not gate anything",
    "no_verdict": "the text reaches no overall verdict, or is not a review report at all"}}}
JSON
    printf '%s' "$CONTENT" >"$S"
    ANSWER=$(bash "$TS_ASK" --questions "$Q" --state "$S" --timeout 8 2>/dev/null) || ANSWER=""
    rm -f "$Q" "$S"
    if [[ -n "$ANSWER" ]] && command -v jq >/dev/null 2>&1; then
        STATUS=$(printf '%s' "$ANSWER" | jq -r --argjson bar "$CONFIDENT_VERDICT" '
          .verdict // {} |
          if (.choice // "no_verdict") != "no_verdict" and (.confidence // 0) >= $bar
          then (.choice | ascii_upcase) else "" end' 2>/dev/null)
    fi
fi

if [[ -z "$STATUS" ]]; then
    echo "NOT_FOUND"
else
    echo "$STATUS"
fi
