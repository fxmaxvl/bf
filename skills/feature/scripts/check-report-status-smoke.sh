#!/usr/bin/env bash
# Smoke test for check-report-status.sh: a single block, several blocks, and the OVERALL escalation.
#
# Usage: check-report-status-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
check="$dir/check-report-status.sh"

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

report() { # complexity consistency review
  printf '## Complexity Report\n\nSTATUS: %s\n\n## Consistency Report\n\nSTATUS: %s\n\n## Implementation Review\n\nSTATUS: %s\n' "$1" "$2" "$3" >"$tmp/r.md"
}
overall() { bash "$check" "$tmp/r.md" "$@" | sed -n 's/^OVERALL: //p'; }
C=(--block "## Complexity Report" --block "## Consistency Report")
A=("${C[@]}" --block "## Implementation Review")

report PASS BLOCK PASS
eq "single block keeps the bare status" "$(bash "$check" "$tmp/r.md" --block '## Consistency Report')" BLOCK
eq "several blocks print one line per block" "$(bash "$check" "$tmp/r.md" "${C[@]}" | sed -n 2p)" "## Consistency Report: BLOCK"
eq "any BLOCK -> BLOCK" "$(overall "${C[@]}")" BLOCK
report PASS ADVISORY PASS
eq "ADVISORY and PASS -> ADVISORY" "$(overall "${A[@]}")" ADVISORY
report PASS PASS PASS
eq "all PASS -> PASS" "$(overall "${A[@]}")" PASS
report PASS ADVISORY CONCERN
eq "CONCERN counts as BLOCK" "$(overall "${A[@]}")" BLOCK
eq "a missing block -> NOT_FOUND" "$(overall "${C[@]}" --block '## Nope')" NOT_FOUND
eq "no file -> NOT_FOUND" "$(bash "$check" "$tmp/none.md" "${C[@]}" | sed -n 's/^OVERALL: //p')" NOT_FOUND

[ "$fails" -eq 0 ]
