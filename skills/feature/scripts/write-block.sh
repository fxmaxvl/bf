#!/usr/bin/env bash
# write-block.sh — Replace or append one `## ` block in a merged artifact file.
# Parallel gate agents write their reports into the same temp file; hand edits
# race, and a replace by line count cuts off a neighbour's block. This anchors
# on the header line and holds an exclusive lock across read → rewrite.
# Usage: bash write-block.sh <file> --block <header> < content
# Outputs: nothing; the file is created if missing
#
# --block <header>  The exact header line, e.g. "## Complexity Report". Matched
#                   whole, so "## Spec" never matches "## Specification".
#
# The block body is read from stdin and must not contain a `## ` line — the
# next `## ` ends a block. A present block is replaced in place; an absent one
# is appended. Every other block stays byte-identical. Regenerate write mode only:
# an accumulate block written through this would be replaced, not extended.

set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
    echo "Usage: write-block.sh <file> --block <header> < content" >&2
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

mkdir -p "$(dirname "$FILE")"

python3 -c "$(cat << 'EOF'
import fcntl
import sys

path, header = sys.argv[1], sys.argv[2]
body = sys.stdin.read().strip('\n')
if any(line.startswith('## ') for line in body.splitlines()):
    sys.exit("Error: block body contains a '## ' line, which would split the block")
block = f"{header}\n\n{body}\n" if body else f"{header}\n"

with open(path, 'a+') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.seek(0)
    lines = f.read().splitlines(keepends=True)

    start = next((i for i, l in enumerate(lines) if l.rstrip() == header), None)
    if start is None:
        prefix = ''.join(lines)
        if prefix and not prefix.endswith('\n'):
            prefix += '\n'
        out = prefix + ('\n' if prefix else '') + block
    else:
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
        rest = ''.join(lines[end:])
        out = ''.join(lines[:start]) + block + ('\n' + rest if rest else '')

    f.seek(0)
    f.truncate()
    f.write(out)
EOF
)" "$FILE" "$BLOCK_HEADER"
