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

# In the consistency format there are no "####" group lines, so an unreadable finding can come
# before the first readable one. It must still reach the report.
printf '## Consistency Report\n\nSTATUS: ADVISORY\n\n### ADVISORY\n\n- src/a.ts:3, **Naming**: path without backticks.\n- `src/c.ts:7`, **Naming**: name differs.\n' >"$tmp/mixed.md"
report ""
bash "$merge" "$tmp/report.md" "$tmp/mixed.md" --consistency >/dev/null
has "an unreadable finding before a readable one is kept" "$tmp/report.md" '- src/a.ts:3, **Naming**: path without backticks.'
has "the readable finding is still numbered" "$tmp/report.md" '- **Y1** [should-consider] `src/c.ts:7`: name differs.'

# measured-gate.sh output sits under "### Advisory Issues". The finding merges as a
# [should-consider] item, and the run summary and note lines are kept (plain lines before the
# first "###" header would be dropped, so the wrapper output never goes there).
cat >"$tmp/measured.md" <<'MD'
## Complexity Report

STATUS: ADVISORY

### Advisory Issues (pre-existing or design risk)

#### Measured / Run summary
Measured: ran crapper. dryer not installed, run /bf:setup. mutator not installed, run /bf:setup.
Measured note: crapper reported 14 findings, showing the worst 10.
#### Measured / High CRAP score — crapper
- `src/demo/board.py:2`: `place` scores CRAP 31.2 (CC 12, coverage 40.0%). **Suggestion:** split the function or cover its branches with tests.
MD
report ""
out=$(bash "$merge" "$tmp/report.md" "$tmp/measured.md" --complexity)
eq "measured findings escalate STATUS to CONCERN" "$out" "STATUS: CONCERN"
has "a measured finding merges as should-consider X1" "$tmp/report.md" '- **X1** [should-consider] `src/demo/board.py:2`: `place` scores CRAP 31.2 (CC 12, coverage 40.0%). Suggested: split the function or cover its branches with tests.'
has "the measured run line is kept" "$tmp/report.md" 'Measured: ran crapper. dryer not installed, run /bf:setup. mutator not installed, run /bf:setup.'
has "the measured note line is kept" "$tmp/report.md" 'Measured note: crapper reported 14 findings, showing the worst 10.'
has "the measured group heading is kept" "$tmp/report.md" '### Measured / High CRAP score — crapper'

# A mutator backup finding is a finding group, so a gate that holds only it is ADVISORY and the
# merge keeps it. The wrapper emits no backup note a PASS gate would drop.
cat >"$tmp/backup.md" <<'MD'
## Complexity Report

STATUS: ADVISORY

### Advisory Issues (pre-existing or design risk)

#### Measured / Run summary
Measured: ran mutator. crapper not installed, run /bf:setup. dryer not installed, run /bf:setup.
#### Measured / Backup copies left — mutator
- `target/mutator-backup`: mutator left copies of source files there. **Suggestion:** run mutator once to restore them.
MD
report ""
out=$(bash "$merge" "$tmp/report.md" "$tmp/backup.md" --complexity)
eq "a mutator backup finding escalates STATUS to CONCERN" "$out" "STATUS: CONCERN"
has "the mutator backup finding merges as should-consider X1" "$tmp/report.md" '- **X1** [should-consider] `target/mutator-backup`: mutator left copies of source files there. Suggested: run mutator once to restore them.'

[ "$fails" -eq 0 ]
