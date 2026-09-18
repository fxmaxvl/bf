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
if [[ -z "$STATUS" ]]; then
    echo "NOT_FOUND"
else
    echo "$STATUS"
fi
