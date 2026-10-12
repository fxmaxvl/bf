#!/usr/bin/env bash
# Smoke test for write-block.sh: create, append, in-place replace, header prefix, rejected body,
# and three concurrent writers on one file.
#
# Usage: write-block-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$dir/write-block.sh
read_block=$dir/read-block.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

f=$tmp/sub/t.md
printf 'spec v1\n' | bash "$script" "$f" --block "## Spec"
eq "missing file and directory created" "$(cat "$f")" "$(printf '## Spec\n\nspec v1')"

printf 'long v1\n### sub\nx\n' | bash "$script" "$f" --block "## Specification"
printf 'c1\n' | bash "$script" "$f" --block "## Complexity Report"
eq "absent header appended after a blank line" "$(cat "$f")" "$(printf '## Spec\n\nspec v1\n\n## Specification\n\nlong v1\n### sub\nx\n\n## Complexity Report\n\nc1')"

before=$(bash "$read_block" "$f" --block "## Specification")
printf 'spec v2\nline2\n' | bash "$script" "$f" --block "## Spec"
eq "existing block replaced in place" "$(bash "$read_block" "$f" --block "## Spec")" "$(printf '\nspec v2\nline2\n')"
eq "prefix header untouched" "$(bash "$read_block" "$f" --block "## Specification")" "$before"
eq "block order kept" "$(grep '^## ' "$f" | tr '\n' '|')" "## Spec|## Specification|## Complexity Report|"

cp "$f" "$tmp/pre"
rc=0; printf 'a\n## evil\n' | bash "$script" "$f" --block "## Spec" 2>/dev/null || rc=$?
eq "body with a ## line rejected" "$rc" 1
eq "rejected write leaves file unchanged" "$(cmp -s "$f" "$tmp/pre" && echo same)" same

r=$tmp/race.md
printf '## QA\n\nqa\n' > "$r"
for name in "Complexity Report" "Consistency Report" "Implementation Review"; do
    ( for i in $(seq 1 20); do printf '%s\nrun %s\n' "$name" "$i" | bash "$script" "$r" --block "## $name"; done ) &
done
wait
eq "concurrent writers keep one header each" "$(grep '^## ' "$r" | sort | tr '\n' '|')" "## Complexity Report|## Consistency Report|## Implementation Review|## QA|"
eq "concurrent writers keep each final body" "$(bash "$read_block" "$r" --block "## Consistency Report")" "$(printf '\nConsistency Report\nrun 20\n')"

[ "$fails" -eq 0 ]
