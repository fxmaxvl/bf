#!/usr/bin/env bash
# Smoke test for measured-gate.sh. A fake HOME holds stub tools that print the captured fixtures,
# so the run installs nothing and never touches the real ~/.bf. Run with bash and macOS /bin/bash.
#
# Usage: measured-gate-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -uo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate=$dir/measured-gate.sh
fx=$dir/fixtures/measured
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is required to run this smoke"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 is required to run this smoke"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1${2:+: $2}"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$2], want [$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$2]" ;; esac; }
lacks() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] in [$2]" ;; *) ok "$1" ;; esac; }

export STUB_LOG=$T/calls.log

reset() {
  rm -rf "$T/home" "$T/proj"; mkdir -p "$T/home" "$T/proj/src/demo" "$T/proj/src/my dir"
  : > "$STUB_LOG"
  unset STUB_CRAPPER_OUT STUB_CRAPPER_RC STUB_CRAPPER_ERR STUB_CRAPPER_METRICS STUB_CRAPPER_SLEEP
  unset STUB_MUTATOR_BACKUP STUB_DRYER_OUT STUB_DRYER_RC STUB_MUTATOR_EDN STUB_MUTATOR_RC STUB_MUTATOR_ERR MEASURED_GATE_BUDGET_S
  printf 'import os\ndef place(x):\n    return x\n\ndef clear(x):\n    return x\n' > "$T/proj/src/demo/board.py"
  printf 'def helper():\n    return 1\n' > "$T/proj/src/my dir/x.py"
  printf '# notes\n' > "$T/proj/NOTES.md"; printf '#!/bin/sh\n' > "$T/proj/run.sh"
}

# A ready tool: launcher, .venv python, and for mutator a crapper sibling.
install_tool() {
  local n=$1 u d
  u=$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')
  d=$T/home/.bf/tools/$n
  mkdir -p "$d/.venv/bin"
  cat > "$d/$n" <<STUB
#!/bin/bash
printf '%s' "$n" >> "\$STUB_LOG"; for a in "\$@"; do printf '|%s' "\$a" >> "\$STUB_LOG"; done; echo >> "\$STUB_LOG"
[ -n "\${STUB_${u}_SLEEP:-}" ] && sleep "\$STUB_${u}_SLEEP"
[ -n "\${STUB_${u}_METRICS:-}" ] && { mkdir -p .metrics; echo '{:entries []}' > .metrics/crap.edn; }
[ -n "\${STUB_${u}_BACKUP:-}" ] && { mkdir -p target/mutator-backup/src; echo old > target/mutator-backup/src/board.py; }
[ -n "\${STUB_${u}_EDN:-}" ] && { mkdir -p .metrics/mutate; cp "\$STUB_${u}_EDN" .metrics/mutate/demo.board.Board.edn; }
[ -n "\${STUB_${u}_OUT:-}" ] && cat "\$STUB_${u}_OUT"
[ -n "\${STUB_${u}_ERR:-}" ] && echo "\$STUB_${u}_ERR" >&2
exit "\${STUB_${u}_RC:-0}"
STUB
  printf '#!/bin/bash\n' > "$d/.venv/bin/python"
  chmod +x "$d/$n" "$d/.venv/bin/python"
}

run() { (cd "$T/proj" && HOME="$T/home" "${BASH:-bash}" "$gate" -- "$@"); }
calls() { cat "$STUB_LOG"; }

reset
out=$(run src/demo/board.py)
expect "no tools gives the first skip line" "$out" "#### Measured / Run summary
Measured: skipped. crapper, dryer and mutator are not installed. Run /bf:setup to add them."

reset; install_tool crapper; install_tool dryer; install_tool mutator
out=$(run NOTES.md run.sh gone.py)
expect "only .sh, .md and missing paths give the second skip line" "$out" "#### Measured / Run summary
Measured: skipped. No changed file is in a supported language."
expect "a skipped run calls no tool" "$(calls)" ""

(cd "$T/proj" && "${BASH:-bash}" "$gate" src/demo/board.py >/dev/null 2>&1); expect "missing -- is a usage error" "$?" "1"

reset; install_tool crapper
mkdir -p "$T/proj/target/coverage/python"; echo "TN:" > "$T/proj/target/coverage/python/lcov.info"
out=$(STUB_CRAPPER_OUT=$fx/crapper-coverage.txt run src/demo/board.py)
has "crapper finding with a coverage report" "$out" '- `src/demo/board.py:2`: `place` scores CRAP 31.2 (CC 12, coverage 40.0%). **Suggestion:** split the function or cover its branches with tests.'
has "crapper group heading" "$out" '#### Measured / High CRAP score — crapper'
lacks "a function under the limit is not reported" "$out" '`clear`'
has "the existing-coverage flag is passed" "$(calls)" 'crapper|--use-existing-coverage|src/demo/board.py'
has "the summary names the run and the missing tools" "$out" 'Measured: ran crapper. dryer not installed, run /bf:setup. mutator not installed, run /bf:setup.'

reset; install_tool crapper
mkdir -p "$T/proj/coverage"; echo "TN:" > "$T/proj/coverage/lcov.info"
STUB_CRAPPER_OUT=$fx/crapper-nocoverage.txt run src/demo/board.py >/dev/null
has "a report for another language does not count" "$(calls)" 'crapper|--no-coverage|src/demo/board.py'

reset; install_tool crapper
out=$(STUB_CRAPPER_OUT=$fx/crapper-nocoverage.txt run src/demo/board.py)
has "crapper without a report reports CC" "$out" '- `src/demo/board.py:2`: `place` scores CC 12, no coverage report. **Suggestion:**'
has "the no-coverage flag is passed" "$(calls)" 'crapper|--no-coverage|src/demo/board.py'
lacks "no crapper finding below CC 10" "$out" '`clear`'

reset; install_tool crapper
out=$(STUB_CRAPPER_RC=1 STUB_CRAPPER_ERR="boom: tree-sitter missing" run src/demo/board.py)
has "a crapper crash gives a note" "$out" 'Measured note: crapper failed on src/demo/board.py: boom: tree-sitter missing'
lacks "a crapper crash gives no finding" "$out" 'High CRAP score'

reset; install_tool crapper
out=$(STUB_CRAPPER_OUT=$fx/crapper-nocoverage.txt run "src/my dir/x.py" src/demo/board.py)
has "a path with a space reaches the tool as one argument" "$(calls)" 'crapper|--no-coverage|src/my dir/x.py'

reset; install_tool dryer
out=$(STUB_DRYER_OUT=$fx/dryer-text.txt run src/demo/board.py "src/my dir/x.py")
has "dryer pair finding" "$out" '- `src/billing/invoice.py:3-13`: matches `src/billing/receipt.py:3-14` at score 0.89. **Suggestion:** extract the shared shape if the two must change together.'
has "dryer finding keeps a path with a space" "$out" '`src/billing/a b.py:20-30`'
has "dryer group heading" "$out" '#### Measured / Duplicate structure — dryer'
has "dryer gets the threshold and every path in one call" "$(calls)" 'dryer|--threshold|0.82|src/demo/board.py|src/my dir/x.py'
out=$(STUB_DRYER_OUT=$fx/dryer-none.txt run src/demo/board.py)
lacks "no duplicates gives no group" "$out" 'Duplicate structure'

reset; install_tool mutator; install_tool crapper
out=$(STUB_MUTATOR_EDN=$fx/mutator-snapshot.edn STUB_MUTATOR_RC=3 run src/demo/board.py)
has "mutator exit 3 gives a finding" "$out" '- `src/demo/board.py:2`: 2 mutants survive in `place`. **Suggestion:** add a test that fails for the mutated behavior.'
has "mutator group heading" "$out" '#### Measured / Surviving mutants — mutator'
lacks "a form without survivors is not reported" "$out" '_hide'
has "mutator gets the no-coverage flag and the path" "$(calls)" 'mutator|--no-coverage|src/demo/board.py'
expect "mutator runs once for all paths" "$(printf '%s' "$(calls)" | grep -c '^mutator')" "1"

reset; install_tool mutator; install_tool crapper
out=$(STUB_MUTATOR_EDN=$fx/mutator-snapshot.edn STUB_MUTATOR_RC=2 run src/demo/board.py)
has "mutator exit 2 gives the baseline note" "$out" 'Measured note: mutator skipped, baseline tests fail.'
lacks "mutator exit 2 gives no finding" "$out" 'Surviving mutants'

reset; install_tool mutator; install_tool crapper
out=$(STUB_MUTATOR_RC=1 STUB_MUTATOR_ERR="Traceback: no module" run src/demo/board.py)
has "another mutator exit gives a note with the first stderr line" "$out" 'Measured note: mutator failed: Traceback: no module'

reset; install_tool crapper
out=$(STUB_CRAPPER_METRICS=1 STUB_CRAPPER_OUT=$fx/crapper-nocoverage.txt run src/demo/board.py)
[ ! -e "$T/proj/.metrics" ] && ok "a .metrics the run created is removed" || bad "a .metrics the run created is removed"

reset; install_tool crapper; mkdir -p "$T/proj/.metrics"; echo keep > "$T/proj/.metrics/keep"
out=$(STUB_CRAPPER_METRICS=1 STUB_CRAPPER_OUT=$fx/crapper-nocoverage.txt run src/demo/board.py)
[ -f "$T/proj/.metrics/keep" ] && ok "a .metrics that existed before stays" || bad "a .metrics that existed before stays"

reset; install_tool mutator; install_tool crapper
out=$(STUB_MUTATOR_BACKUP=1 STUB_MUTATOR_RC=3 run src/demo/board.py)
[ -f "$T/proj/target/mutator-backup/src/board.py" ] && ok "target is kept while mutator backups exist" || bad "target is kept while mutator backups exist"
has "the kept backups are named in a note" "$out" 'Measured note: mutator left copies under target/mutator-backup.'

reset; install_tool dryer
out=$(STUB_DRYER_OUT=$fx/dryer-text.txt run src/demo/board.py)
has "a partial install runs the ready tools" "$out" 'Measured: ran dryer. crapper not installed, run /bf:setup. mutator not installed, run /bf:setup.'

reset; install_tool crapper
start=$(date +%s)
out=$(MEASURED_GATE_BUDGET_S=2 STUB_CRAPPER_SLEEP=20 STUB_CRAPPER_OUT=$fx/crapper-nocoverage.txt run src/demo/board.py)
elapsed=$(( $(date +%s) - start ))
has "a tool past its time limit gives a note" "$out" 'Measured note: crapper hit its time limit'
[ "$elapsed" -lt 15 ] && ok "a timeout stops the tool at the budget" || bad "a timeout stops the tool at the budget" "took ${elapsed}s"

expect "the heading format is documented once, in the wrapper" "$(grep -c '^#   #### Measured / ' "$gate")" "4"
grep -q 'TOTAL_BUDGET_S = int(os.environ.get("MEASURED_GATE_BUDGET_S", "540"))' "$gate" && ok "the default budget is 540 s" || bad "the default budget is 540 s"

gate_skill=$dir/../complexity-gate/SKILL.md
grep -q 'timeout: 600000' "$gate_skill" && grep -q '540 s' "$gate_skill" && ok "the gate passes timeout 600000 and names the 540 s budget" || bad "the gate passes timeout 600000 and names the 540 s budget"
expect "the gate copies the wrapper heading format by reference" "$(grep -c '^#### Measured / ' "$gate_skill")" "2"

echo "---- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
