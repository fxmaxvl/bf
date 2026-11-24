#!/usr/bin/env bash
# Run crapper, dryer and mutator on the given files and print advisory findings.
# This wrapper is the only code that runs those three tools. The complexity gate Agent can run
# only `bash <script>`, and the tools need a time limit that a bare call does not give.
#
# Usage:  measured-gate.sh -- <path>...      (paths relative to the current directory)
# Output: plain text, exit 0 except on bad arguments. The text is ready to copy into the
#         complexity report. It holds a run summary group, then zero or more finding groups.
#         The "#### Measured / ..." heading format is defined only here:
#
#   #### Measured / Run summary
#   Measured: skipped. crapper, dryer and mutator are not installed. Run /bf:setup to add them.
#   Measured: skipped. No changed file is in a supported language.
#   Measured: ran <tools>.[ <tool> not installed, run /bf:setup.]
#   Measured note: <one line per problem>
#   #### Measured / High CRAP score — crapper
#   - `<file>:<line>`: `<function>` scores CRAP <n> (CC <cc>, coverage <p>%). **Suggestion:** ...
#   #### Measured / Duplicate structure — dryer
#   - `<fileA>:<a1>-<a2>`: matches `<fileB>:<b1>-<b2>` at score <s>. **Suggestion:** ...
#   #### Measured / Surviving mutants — mutator
#   - `<file>:<line>`: <k> mutants survive in `<function>`. **Suggestion:** ...
#
# The em dash in two group headings is a parsed literal of the complexity Report Format, and
# merge-gate-reports.sh reads these lines as Advisory findings. Change the format, the gate
# template and that parser together, then run measured-gate-smoke.sh and
# merge-gate-reports-smoke.sh.
#
# Time limit: the run uses at most TOTAL_BUDGET_S seconds (540), set in the Python block below. The
# complexity-gate SKILL.md passes `timeout: 600000` (600 s) on the call. Keep the budget under
# that value, and change both together. measured-gate-smoke.sh checks the pair.
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

SETUP_SH="$here/../../setup/scripts/setup.sh" exec python3 - "$@" <<'PY'
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

TOTAL_BUDGET_S = int(os.environ.get("MEASURED_GATE_BUDGET_S", "540"))  # the override is test-only
CRAPPER_BUDGET_S = 90
DRYER_BUDGET_S = 90
CRAP_LIMIT = 10
DRY_THRESHOLD = "0.82"
MAX_FINDINGS = 10
SUPPORTED = {".clj", ".cljs", ".cljc", ".java", ".go", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".rs", ".py"}
TOOLS = ["crapper", "dryer", "mutator"]
SETUP_HINT = "Run /bf:setup to add them."

started = time.time()
out_lines = []


def emit(line):
    out_lines.append(line)


def first_line(text):
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:200]
    return "no output"


def run_tool(cmd, limit):
    """Run cmd for at most limit seconds. Returns (returncode, stdout, stderr), or None on timeout."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                            stdin=subprocess.DEVNULL, start_new_session=True)
    try:
        stdout, stderr = proc.communicate(timeout=limit)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return None
    return proc.returncode, stdout, stderr


def find_line(path, name):
    """crapper prints no line number, so this is the first line that declares the name."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return 1
    word = re.escape(name)
    declared = re.compile(r"\b(?:def|fn|func|function|defn-?|fun)\s+(?:\([^)]*\)\s*)?" + word + r"\b")
    called = re.compile(r"\b" + word + r"\s*[(=:]")
    for pattern in (declared, called):
        for number, line in enumerate(lines, 1):
            if pattern.search(line):
                return number
    return 1


def has_report(path):
    """True when a coverage report for the language of path is on disk (the paths crapper reads)."""
    ext = os.path.splitext(path)[1]
    if ext in (".clj", ".cljs", ".cljc"):
        return os.path.isdir("target/coverage")
    if ext == ".java":
        return os.path.isfile("target/site/jacoco/jacoco.xml")
    if ext == ".go":
        return os.path.isfile("target/coverage/go/coverage.out")
    if ext == ".rs":
        return os.path.isfile("target/coverage/rust/lcov.info")
    if ext == ".py":
        return os.path.isfile("target/coverage/python/lcov.info")
    return os.path.isfile("coverage/lcov.info") or os.path.isfile("target/coverage/typescript/lcov.info")


def coverage_flag(has):
    return "--use-existing-coverage" if has else "--no-coverage"


def parse_crapper(text):
    rows = []
    after_rule = False
    for line in text.splitlines():
        if line.startswith("---"):
            after_rule = True
            continue
        parts = line.split()
        if not after_rule or len(parts) < 5:
            continue
        name, cc, cov, crap = parts[0], parts[-3], parts[-2], parts[-1]
        if not cc.isdigit():
            continue
        rows.append((name, int(cc), None if cov == "N/A" else float(cov.rstrip("%")),
                     None if crap == "N/A" else float(crap)))
    return rows


def parse_dryer(text):
    found = []
    score = None
    spans = []
    for line in text.splitlines():
        match = re.match(r"^DUPLICATE score=([0-9.]+)$", line)
        if match:
            score, spans = match.group(1), []
            continue
        match = re.match(r"^  (.+):(\d+)-(\d+)$", line)
        if match and score is not None:
            spans.append((match.group(1), match.group(2), match.group(3)))
            if len(spans) == 2:
                found.append((score, spans[0], spans[1]))
                score = None
    return found


def edn_string(value):
    return value.replace('\\"', '"').replace("\\\\", "\\")


def parse_mutator_snapshots(paths):
    """Read the forms of .metrics/mutate/*.edn. The stdout table has no file or line."""
    wanted = set(paths)
    found = []
    for snapshot in sorted(glob.glob(os.path.join(".metrics", "mutate", "*.edn"))):
        try:
            with open(snapshot, encoding="utf-8") as handle:
                text = handle.read()
        except OSError:
            continue
        source = re.search(r':source "((?:[^"\\]|\\.)*)"', text)
        source = edn_string(source.group(1)) if source else None
        if source not in wanted:
            continue
        for form in re.finditer(r'\{:id "((?:[^"\\]|\\.)*)"([^{}]*)\}', text):
            body = form.group(2)
            survived = re.search(r":survived (\d+)", body)
            if not survived or int(survived.group(1)) == 0:
                continue
            line = re.search(r":line (\d+)", body)
            file_ = re.search(r':file "((?:[^"\\]|\\.)*)"', body)
            name = edn_string(form.group(1)).split("/", 1)[-1]
            found.append((edn_string(file_.group(1)) if file_ else source, int(line.group(1)) if line else 1,
                          int(survived.group(1)), name))
    return found


def main():
    paths = [p for p in sys.argv[1:] if os.path.splitext(p)[1] in SUPPORTED and os.path.isfile(p)]
    emit("#### Measured / Run summary")
    if not paths:
        emit("Measured: skipped. No changed file is in a supported language.")
        return

    ready = {}
    try:
        checked = subprocess.run(["bash", os.environ["SETUP_SH"], "check"] + TOOLS, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, universal_newlines=True, stdin=subprocess.DEVNULL)
        data = json.loads(checked.stdout)
    except (OSError, ValueError):
        data = {}
    if "error" in data:
        emit("Measured: skipped. The tool check failed: %s. %s" % (data.get("error"), SETUP_HINT))
        return
    for tool in TOOLS:
        entry = data.get(tool) or {}
        if entry.get("ready"):
            ready[tool] = entry["path"]
    if not ready:
        emit("Measured: skipped. crapper, dryer and mutator are not installed. " + SETUP_HINT)
        return

    deadline = started + TOTAL_BUDGET_S
    existed = {name: os.path.exists(name) for name in (".metrics", "target", "coverage")}
    notes = []
    groups = []
    ran = []

    def remaining(cap_deadline):
        return min(cap_deadline, deadline) - time.time()

    if "crapper" in ready:
        ran.append("crapper")
        cap = time.time() + CRAPPER_BUDGET_S
        rows = []
        failure = None
        for path in paths:
            limit = remaining(cap)
            if limit <= 1:
                notes.append("crapper hit its time limit, later files were not scored.")
                break
            covered = has_report(path)
            result = run_tool([ready["crapper"], coverage_flag(covered), path], limit)
            if result is None:
                notes.append("crapper hit its time limit, later files were not scored.")
                break
            code, stdout, stderr = result
            if code != 0:
                failure = failure or "crapper failed on %s: %s" % (path, first_line(stderr or stdout))
                continue
            for name, cc, cov, crap in parse_crapper(stdout):
                score = crap if (covered and crap is not None) else None
                if (score is not None and score >= CRAP_LIMIT) or (score is None and cc >= CRAP_LIMIT):
                    rows.append((score if score is not None else cc, path, name, cc, cov, score))
        if failure:
            notes.append(failure)
        if rows:
            rows.sort(key=lambda r: -r[0])
            if len(rows) > MAX_FINDINGS:
                notes.append("crapper reported %d findings, showing the worst %d." % (len(rows), MAX_FINDINGS))
            lines = ["#### Measured / High CRAP score — crapper"]
            for _, path, name, cc, cov, score in rows[:MAX_FINDINGS]:
                where = "`%s:%d`" % (path, find_line(path, name))
                if score is not None:
                    detail = "scores CRAP %s (CC %d, coverage %s%%)" % (("%.1f" % score), cc, ("%.1f" % (cov or 0.0)))
                else:
                    detail = "scores CC %d, no coverage report" % cc
                lines.append("- %s: `%s` %s. **Suggestion:** split the function or cover its branches with tests."
                             % (where, name, detail))
            groups.append(lines)

    if "dryer" in ready:
        ran.append("dryer")
        limit = remaining(time.time() + DRYER_BUDGET_S)
        result = run_tool([ready["dryer"], "--threshold", DRY_THRESHOLD] + paths, limit) if limit > 1 else None
        if result is None:
            notes.append("dryer hit its time limit, no duplicates reported.")
        elif result[0] != 0:
            notes.append("dryer failed: %s" % first_line(result[2] or result[1]))
        else:
            pairs = parse_dryer(result[1])
            if len(pairs) > MAX_FINDINGS:
                notes.append("dryer reported %d pairs, showing the closest %d." % (len(pairs), MAX_FINDINGS))
            if pairs:
                lines = ["#### Measured / Duplicate structure — dryer"]
                for score, left, right in pairs[:MAX_FINDINGS]:
                    lines.append("- `%s:%s-%s`: matches `%s:%s-%s` at score %s. **Suggestion:** extract the shared shape "
                                 "if the two must change together." % (left + right + (score,)))
                groups.append(lines)

    if "mutator" in ready:
        ran.append("mutator")
        limit = remaining(deadline)
        mutator_flag = coverage_flag(all(has_report(p) for p in paths))
        result = run_tool([ready["mutator"], mutator_flag] + paths, limit) if limit > 1 else None
        if result is None:
            notes.append("mutator hit the time budget, no mutation result reported.")
        elif result[0] == 2:
            notes.append("mutator skipped, baseline tests fail.")
        elif result[0] not in (0, 3):
            notes.append("mutator failed: %s" % first_line(result[2] or result[1]))
        else:
            survivors = parse_mutator_snapshots(paths)
            if survivors:
                lines = ["#### Measured / Surviving mutants — mutator"]
                for file_, line, count, name in survivors[:MAX_FINDINGS]:
                    lines.append("- `%s:%d`: %d %s in `%s`. **Suggestion:** add a test that fails for the mutated behavior."
                                 % (file_, line, count, "mutant survives" if count == 1 else "mutants survive", name))
                if len(survivors) > MAX_FINDINGS:
                    notes.append("mutator reported %d functions with survivors, showing %d." % (len(survivors), MAX_FINDINGS))
                groups.append(lines)

    for name in (".metrics", "target", "coverage"):
        if existed[name] or not os.path.isdir(name):
            continue
        if name == "target" and any(files for _, _, files in os.walk("target/mutator-backup")):
            notes.append("mutator left copies under target/mutator-backup. Run mutator once to restore them.")
            continue
        shutil.rmtree(name, ignore_errors=True)

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
