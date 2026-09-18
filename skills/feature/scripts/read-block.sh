#!/usr/bin/env bash
# read-block.sh — Print one `## ` block's body from a merged artifact file.
# Replaces the model grepping for the header, grepping for the next `## `, then
# issuing an offset/limit read — three round-trips for one block.
# Usage: bash read-block.sh <file> --block <header>
# Outputs: the block body on stdout, or nothing
#
# --block <header>  The exact header line, e.g. "## Spec". Matched whole, so
#                   "## Spec" never matches "## Specification".
#
# Empty output means the block is absent or empty, or the file does not exist —
# callers treat all three the same, as the optional-block call sites already do.

set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
    echo "Usage: read-block.sh <file> --block <header>" >&2
    exit 1
fi

if [[ "${2:-}" != "--block" ]]; then
    echo "Error: --block <header> is required" >&2
    exit 1
fi

BLOCK_HEADER="${3:-}"
if [[ -z "$BLOCK_HEADER" ]]; then
    echo "Error: --block requires a header argument" >&2
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    exit 0
fi

python3 - "$FILE" "$BLOCK_HEADER" << 'EOF'
import sys

path, header = sys.argv[1], sys.argv[2]
lines = open(path).readlines()
in_block = False
block_lines = []
for line in lines:
    if line.rstrip() == header:
        in_block = True
        continue
    if in_block:
        if line.startswith('## ') and line.rstrip() != header:
            break
        block_lines.append(line)
print(''.join(block_lines), end='')
EOF
