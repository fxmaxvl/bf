#!/usr/bin/env bash
# check-report-status.sh — Extract the STATUS line from a review or complexity report.
# Replaces the model reading an entire report file just to check one line.
# Usage: bash check-report-status.sh <report-file>
# Outputs: PASS | CONCERN | BLOCK | ADVISORY | NOT_FOUND

set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
    echo "Usage: check-report-status.sh <file>" >&2
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    echo "NOT_FOUND"
    exit 0
fi

STATUS=$(grep -m1 -E '^STATUS:' "$FILE" | sed 's/^STATUS:[[:space:]]*//' | tr -d '[:space:]')
if [[ -z "$STATUS" ]]; then
    echo "NOT_FOUND"
else
    echo "$STATUS"
fi
