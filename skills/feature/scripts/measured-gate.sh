#!/usr/bin/env bash
# Run crapper, dryer and mutator on the given files and print advisory findings.
# The runner and the parsers live in measured_tools.py, shared with refactor-scout's scout.py. The
# complexity gate Agent can run only `bash <script>`, and the tools need a time limit that a bare call
# does not give.
#
# Usage:  measured-gate.sh -- <path>...      (paths relative to the current directory)
# Output: plain text, exit 0 except on bad arguments. The text is ready to copy into the
#         complexity report. It holds a run summary group, then zero or more finding groups.
#         The "#### Measured / ..." heading format is defined only here:
#
#   #### Measured / Run summary
#   Measured: skipped. python3 is not installed. Run /bf:setup to add it.
#   Measured: skipped. The tool check failed: <error>. Run /bf:setup to add them.
#   Measured: skipped. crapper, dryer and mutator are not installed. Run /bf:setup to add them.
#   Measured: skipped. No changed file is in a supported language.
#   Measured: ran <tools>.[ <tool> not installed, run /bf:setup.]
#   Measured note: <one line per problem>
#   #### Measured / High CRAP score — crapper
#   - `<file>:<line>`: `<function>` scores CRAP <n> (CC <cc>, coverage <p>%). **Suggestion:** ...
#   - `<file>:<line>`: `<function>` scores CC <cc>, no coverage report. **Suggestion:** ...
#   - `<file>:<line>`: `<function>` scores CC <cc>, no coverage data for this function. **Suggestion:** ...
#   #### Measured / Duplicate structure — dryer
#   - `<fileA>:<a1>-<a2>`: matches `<fileB>:<b1>-<b2>` at score <s>. **Suggestion:** ...
#   #### Measured / Surviving mutants — mutator
#   - `<file>:<line>`: <k> mutants survive in `<function>`. **Suggestion:** ...
#   #### Measured / Backup copies left — mutator
#   - `target/mutator-backup`: mutator left copies of source files there. **Suggestion:** ...
# The backup copies are a finding, not a note: a note under STATUS PASS never reaches /bf:review,
# and a finding turns the gate into ADVISORY.
#
# The em dash in the group headings is a parsed literal of the complexity Report Format, and
# merge-gate-reports.sh reads these lines as Advisory findings. Change the format, the gate
# template and that parser together, then run measured-gate-smoke.sh and
# merge-gate-reports-smoke.sh.
#
# Time limit: the run uses at most TOTAL_BUDGET_S seconds (540), set in the Python block below. The
# complexity-gate SKILL.md passes `timeout: 600000` (600 s) on the call. Keep the budget under
# that value, and change both together. measured-gate-smoke.sh checks the pair.
#
# Side effect: the tools write .metrics, target and coverage in the current directory, and mutator
# writes target/mutation-workers. After the run the wrapper removes each of them that did not exist
# before it started, even when target itself did.
#
# Why it passes explicit paths: all three tools implement --changed as `git status`, which sees
# the working tree only. A committed branch or a PR would show no change.
set -uo pipefail

[ "${1:-}" = "--" ] || { echo "Usage: measured-gate.sh -- <path>..." >&2; exit 1; }
shift

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v python3 >/dev/null 2>&1; then
  printf '#### Measured / Run summary\nMeasured: skipped. python3 is not installed. Run /bf:setup to add it.\n'
  exit 0
fi

PYTHONDONTWRITEBYTECODE=1 MEASURED_TOOLS_DIR="$here" SETUP_SH="$here/../../setup/scripts/setup.sh" exec python3 - "$@" <<'PY'
import os
import sys
import time

sys.path.insert(0, os.environ["MEASURED_TOOLS_DIR"])
from measured_tools import (TOOLS, SUPPORTED, check_tools, coverage_flag, find_line, has_report,  # noqa: E402
                            mutator_backups_left, mutator_mode, run_crapper, run_dirs_cleaned, run_dryer,
                            run_mutator, USE_COVERAGE)

TOTAL_BUDGET_S = int(os.environ.get("MEASURED_GATE_BUDGET_S", "540"))  # the override is test-only
CRAPPER_BUDGET_S = 90
DRYER_BUDGET_S = 90
MAX_FINDINGS = 10
SETUP_HINT = "Run /bf:setup to add them."
BACKUP_HEADING = "#### Measured / Backup copies left — mutator"

started = time.time()
out_lines = []


def emit(line):
    out_lines.append(line)


def main():
    paths = [p for p in sys.argv[1:] if os.path.splitext(p)[1] in SUPPORTED and os.path.isfile(p)]
    emit("#### Measured / Run summary")
    if not paths:
        emit("Measured: skipped. No changed file is in a supported language.")
        return

    ready, error = check_tools(os.environ["SETUP_SH"])
    if error:
        emit("Measured: skipped. The tool check failed: %s. %s" % (error, SETUP_HINT))
        return
    if not ready:
        emit("Measured: skipped. crapper, dryer and mutator are not installed. " + SETUP_HINT)
        return

    deadline = started + TOTAL_BUDGET_S
    notes = []
    groups = []
    ran = []

    def remaining(cap_deadline):
        return min(cap_deadline, deadline) - time.time()

    with run_dirs_cleaned():
        if "crapper" in ready:
            ran.append("crapper")
            cap = time.time() + CRAPPER_BUDGET_S
            rows = run_crapper(ready["crapper"], paths, lambda p: coverage_flag(has_report(p)),
                               lambda: remaining(cap), notes)
            if rows:
                rows.sort(key=lambda r: -r["score"])
                if len(rows) > MAX_FINDINGS:
                    notes.append("crapper reported %d findings, showing the worst %d." % (len(rows), MAX_FINDINGS))
                lines = ["#### Measured / High CRAP score — crapper"]
                for row in rows[:MAX_FINDINGS]:
                    covered = row["mode"] == USE_COVERAGE
                    where = "`%s:%d`" % (row["file"], find_line(row["file"], row["function"]))
                    if row["crap"] is not None:
                        detail = "scores CRAP %s (CC %d, coverage %s%%)" % (
                            "%.1f" % row["crap"], row["cc"], "%.1f" % (row["coverage"] or 0.0))
                    else:
                        detail = "scores CC %d, %s" % (
                            row["cc"], "no coverage data for this function" if covered else "no coverage report")
                    lines.append("- %s: `%s` %s. **Suggestion:** split the function or cover its branches with tests."
                                 % (where, row["function"], detail))
                groups.append(lines)

        if "dryer" in ready:
            ran.append("dryer")
            cap = time.time() + DRYER_BUDGET_S
            pairs = run_dryer(ready["dryer"], paths, lambda: remaining(cap), notes)
            if len(pairs) > MAX_FINDINGS:
                notes.append("dryer reported %d pairs, showing the closest %d." % (len(pairs), MAX_FINDINGS))
            if pairs:
                lines = ["#### Measured / Duplicate structure — dryer"]
                for pair in pairs[:MAX_FINDINGS]:
                    left, right = pair["a"], pair["b"]
                    lines.append("- `%s:%d-%d`: matches `%s:%d-%d` at score %s. **Suggestion:** extract the shared shape "
                                 "if the two must change together."
                                 % (left["file"], left["start"], left["end"], right["file"], right["start"],
                                    right["end"], pair["score_text"]))
                groups.append(lines)

        if "mutator" in ready:
            ran.append("mutator")
            survivors = run_mutator(ready["mutator"], paths, mutator_mode(paths), lambda: remaining(deadline), notes)
            if survivors:
                lines = ["#### Measured / Surviving mutants — mutator"]
                for row in survivors[:MAX_FINDINGS]:
                    count = row["survived"]
                    lines.append("- `%s:%d`: %d %s in `%s`. **Suggestion:** add a test that fails for the mutated behavior."
                                 % (row["file"], row["line"], count, "mutant survives" if count == 1 else "mutants survive",
                                    row["function"]))
                if len(survivors) > MAX_FINDINGS:
                    notes.append("mutator reported %d functions with survivors, showing %d." % (len(survivors), MAX_FINDINGS))
                groups.append(lines)

    if mutator_backups_left():
        groups.append([BACKUP_HEADING,
                       "- `target/mutator-backup`: mutator left copies of source files there. "
                       "**Suggestion:** run mutator once to restore them."])

    missing = [t for t in TOOLS if t not in ready]
    summary = "Measured: ran %s." % (ran[0] if len(ran) == 1 else ", ".join(ran[:-1]) + " and " + ran[-1])
    for tool in missing:
        summary += " %s not installed, run /bf:setup." % tool
    emit(summary)
    for note in notes:
        emit("Measured note: " + note)
    for lines in groups:
        for line in lines:
            emit(line)


main()
sys.stdout.write("\n".join(out_lines) + "\n")
PY
