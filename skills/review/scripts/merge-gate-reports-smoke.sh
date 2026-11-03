#!/usr/bin/env bash
# Smoke test for merge-gate-reports.sh: renumbering, severity mapping, UNKNOWN, STATUS escalation.
#
# Usage: merge-gate-reports-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
merge="$dir/merge-gate-reports.sh"

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }
has() { if grep -qF -- "$3" "$2"; then echo "PASS $1"; else echo "FAIL $1: missing [$3]"; fails=$((fails+1)); fi; }

cat >"$tmp/gates.md" <<'MD'
## Complexity Report

STATUS: BLOCK

### Blocked Issues (introduced this session — must resolve before proceeding)

#### Change amplification / shotgun edit — Repetition
- `src/a.ts:10`: the same rule is copied in three places. **Fix:** extract one helper.

### Advisory Issues (pre-existing or design risk)

#### Pass-through / thin wrapper — Shallow module
- `src/b.ts:4`: wrapper adds nothing. **Suggestion:** inline it.

## Consistency Report

STATUS: ADVISORY

### ADVISORY — inconsistency detected (pre-existing or design risk)

- `src/c.ts:7`, **Naming**: name differs from the sibling module. **Suggestion:** rename it.
MD

report() { printf '# Code Review Report\n- Focus: full\n\nSTATUS: PASS%s\n\n## Summary\nx\n' "$1" >"$tmp/report.md"; }

report ""
out=$(bash "$merge" "$tmp/report.md" "$tmp/gates.md" --complexity --consistency)
eq "prints the STATUS line it wrote" "$out" "STATUS: CONCERN"
has "complexity BLOCK -> [must-fix] X1" "$tmp/report.md" '- **X1** [must-fix] `src/a.ts:10`: the same rule is copied in three places. Suggested: extract one helper.'
has "complexity ADVISORY -> [should-consider] X2" "$tmp/report.md" '- **X2** [should-consider] `src/b.ts:4`: wrapper adds nothing. Suggested: inline it.'
has "consistency numbered Y1 under its lens" "$tmp/report.md" '- **Y1** [should-consider] `src/c.ts:7`: name differs from the sibling module. Suggested: rename it.'
has "consistency groups by lens" "$tmp/report.md" '### Naming'

report " (focus: quality)"
bash "$merge" "$tmp/report.md" "$tmp/gates.md" --consistency >/dev/null
has "focus suffix survives escalation" "$tmp/report.md" 'STATUS: CONCERN (focus: quality)'
eq "a gate the focus did not enable is omitted" "$(grep -c '^## Complexity' "$tmp/report.md")" 0

printf '## Complexity Report\n\nSTATUS: PASS\n' >"$tmp/pass.md"
report ""
bash "$merge" "$tmp/report.md" "$tmp/pass.md" --complexity >/dev/null
eq "PASS gate keeps STATUS PASS" "$(grep -m1 '^STATUS:' "$tmp/report.md")" "STATUS: PASS"
has "PASS gate has no body" "$tmp/report.md" '## Complexity'

report ""
bash "$merge" "$tmp/report.md" "$tmp/none.md" --complexity >/dev/null
has "missing gate file -> UNKNOWN" "$tmp/report.md" 'STATUS: UNKNOWN (complexity gate failed — see conversation)'

report ""
bash "$merge" "$tmp/report.md" "$tmp/none.md" --review-failed >/dev/null
eq "--review-failed forces CONCERN" "$(grep -m1 '^STATUS:' "$tmp/report.md")" "STATUS: CONCERN"

# A BLOCK gate whose finding line the parser cannot read (no backticks around the path) must not
# leave the report at PASS.
printf '## Complexity Report\n\nSTATUS: BLOCK\n\n### Blocked Issues (introduced this session)\n\n#### Group\n- src/a.ts:10: path without backticks. **Fix:** quote it.\n' >"$tmp/odd.md"
report ""
out=$(bash "$merge" "$tmp/report.md" "$tmp/odd.md" --complexity)
eq "unparseable BLOCK finding -> CONCERN, not PASS" "$out" "STATUS: CONCERN"
has "unparseable BLOCK finding is kept verbatim" "$tmp/report.md" '- src/a.ts:10: path without backticks. **Fix:** quote it.'

[ "$fails" -eq 0 ]
