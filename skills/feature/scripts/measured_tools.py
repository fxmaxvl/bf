"""Run crapper, dryer and mutator and parse their output.

measured-gate.sh and refactor-scout's scout.py import this module. Each tool has one runner function that builds
the command, runs it, reads the exit code and returns parsed rows, and the notes go to a list the caller passes in.
The report text each caller builds from those rows stays with that caller.

The functions read and write paths relative to the current directory, which must be the repository root. The tools
write .metrics, target and coverage there, and has_report, parse_mutator_snapshots, mutator_backups_left and
run_dirs_cleaned look at the same place, so they give wrong results from any other directory.
"""
import contextlib
import glob
import json
import os
import re
import shutil
import signal
import subprocess

TOOLS = ["crapper", "dryer", "mutator"]
TERM_GRACE_S = 5
CRAP_LIMIT = 10
DRY_THRESHOLD = "0.82"  # the string is the exact dryer argument
USE_COVERAGE = "--use-existing-coverage"
NO_COVERAGE = "--no-coverage"
# The extensions the gate filters on. dryer reads none of the JavaScript ones, mutator reads exactly these, and
# crapper also reads .bb, .mts and .cts. TOOL_EXTS has each tool's own set.
SUPPORTED = {".clj", ".cljs", ".cljc", ".java", ".go", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".rs", ".py"}
# From each tool's --help. dryer reads no JavaScript, crapper and mutator do.
TOOL_EXTS = {
    "crapper": {".clj", ".cljc", ".cljs", ".bb", ".java", ".go", ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx",
                ".mjs", ".cjs", ".rs", ".py"},
    "dryer": {".clj", ".cljc", ".cljs", ".cljd", ".bb", ".java", ".go", ".ts", ".tsx", ".mts", ".cts", ".rs", ".py"},
    "mutator": {".clj", ".cljc", ".cljs", ".java", ".go", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".rs", ".py"},
}
# Listed children first: mutator's worker trees hold symlinks into the project, so they go even when target stays.
RUN_DIRS = (".metrics", "target/mutation-workers", "target", "coverage")


def first_line(text):
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:200]
    return "no output"


def signal_group(proc, sig):
    try:
        os.killpg(proc.pid, sig)
    except OSError:
        pass


def run_tool(cmd, limit):
    """Run cmd for at most limit seconds. Returns (returncode, stdout, stderr), or None on timeout.
    A tool past its limit gets SIGTERM, so it can remove its own temporary trees, then SIGKILL after TERM_GRACE_S."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                            stdin=subprocess.DEVNULL, start_new_session=True)
    try:
        stdout, stderr = proc.communicate(timeout=limit)
    except subprocess.TimeoutExpired:
        signal_group(proc, signal.SIGTERM)
        try:
            proc.communicate(timeout=TERM_GRACE_S)
        except subprocess.TimeoutExpired:
            pass
        signal_group(proc, signal.SIGKILL)
        proc.communicate()
        return None
    return proc.returncode, stdout, stderr


def check_tools(setup_sh, tools=TOOLS):
    """Return (ready, error): ready maps each installed tool to its path, error is setup.sh's error or None."""
    try:
        checked = subprocess.run(["bash", setup_sh, "check"] + list(tools), stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, universal_newlines=True, stdin=subprocess.DEVNULL)
        data = json.loads(checked.stdout)
    except (OSError, ValueError):
        data = {}
    if "error" in data:
        return {}, data.get("error")
    ready = {}
    for tool in tools:
        entry = data.get(tool) or {}
        if entry.get("ready"):
            ready[tool] = entry["path"]
    return ready, None


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
    if ext in (".clj", ".cljs", ".cljc", ".cljd", ".bb"):
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
    return USE_COVERAGE if has else NO_COVERAGE


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


def survivor_row(form, source):
    """One (file, line, survived, function) tuple for a snapshot form with survivors, else None."""
    body = form.group(2)
    survived = re.search(r":survived (\d+)", body)
    if not survived or int(survived.group(1)) == 0:
        return None
    line = re.search(r":line (\d+)", body)
    file_ = re.search(r':file "((?:[^"\\]|\\.)*)"', body)
    name = edn_string(form.group(1)).split("/", 1)[-1]
    return (edn_string(file_.group(1)) if file_ else source, int(line.group(1)) if line else 1,
            int(survived.group(1)), name)


def snapshot_survivors(text, wanted):
    source = re.search(r':source "((?:[^"\\]|\\.)*)"', text)
    source = edn_string(source.group(1)) if source else None
    if source not in wanted:
        return []
    forms = re.finditer(r'\{:id "((?:[^"\\]|\\.)*)"([^{}]*)\}', text)
    return [row for row in (survivor_row(form, source) for form in forms) if row]


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
        found += snapshot_survivors(text, wanted)
    return found


def mutator_backups_left():
    return any(files for _, _, files in os.walk("target/mutator-backup"))


def crapper_rows(file_, mode, text):
    """The functions of one crapper report at or over CRAP_LIMIT. Without coverage the score is the complexity."""
    rows = []
    for name, cc, cov, crap in parse_crapper(text):
        score = crap if (mode == USE_COVERAGE and crap is not None) else None
        value = score if score is not None else cc
        if value >= CRAP_LIMIT:
            rows.append({"file": file_, "function": name, "cc": cc, "coverage": cov, "crap": score,
                         "score": value, "mode": mode})
    return rows


def run_crapper(path, files, mode_for, limit_for, notes):
    """Run crapper once per file. mode_for(file) gives the coverage flag and limit_for() the seconds left for the
    next call. Returns the rows at or over CRAP_LIMIT and adds the time-limit and failure notes."""
    rows = []
    failure = None
    for file_ in files:
        limit = limit_for()
        mode = mode_for(file_)
        result = run_tool([path, mode, file_], limit) if limit > 1 else None
        if result is None:
            notes.append("crapper hit its time limit, later files were not scored.")
            break
        code, stdout, stderr = result
        if code != 0:
            failure = failure or "crapper failed on %s: %s" % (file_, first_line(stderr or stdout))
            continue
        rows += crapper_rows(file_, mode, stdout)
    if failure:
        notes.append(failure)
    return rows


def dryer_rows(text):
    """One row per pair: score, score_text (the score as dryer printed it) and the spans a and b."""
    rows = []
    for score, left, right in parse_dryer(text):
        sides = [{"file": f, "start": int(a), "end": int(b)} for f, a, b in (left, right)]
        rows.append({"score": float(score), "score_text": score, "a": sides[0], "b": sides[1]})
    return rows


def run_dryer(path, files, limit_for, notes):
    """Run dryer over all files at DRY_THRESHOLD. limit_for() gives the seconds left. Returns the pair rows,
    empty after a note."""
    limit = limit_for()
    result = run_tool([path, "--threshold", DRY_THRESHOLD] + files, limit) if limit > 1 else None
    if result is None:
        notes.append("dryer hit its time limit, no duplicates reported.")
        return []
    if result[0] != 0:
        notes.append("dryer failed: %s" % first_line(result[2] or result[1]))
        return []
    return dryer_rows(result[1])


def mutator_mode(files):
    return coverage_flag(all(has_report(f) for f in files))


def mutator_rows(snapshots):
    """One row per function with survivors, from the (file, line, survived, function) snapshot tuples."""
    return [{"file": f, "line": line, "survived": n, "function": name, "score": n} for f, line, n, name in snapshots]


def run_mutator(path, files, mode, limit_for, notes):
    """Run mutator. limit_for() gives the seconds left. Exit code 2 means it skipped the run, 0 and 3 mean a result.
    Returns one row per function with survivors, or None after a note, so a caller can tell a skipped run from a
    clean one."""
    limit = limit_for()
    result = run_tool([path, mode] + files, limit) if limit > 1 else None
    if result is None:
        notes.append("mutator hit the time budget, no mutation result reported.")
        return None
    if result[0] == 2:
        notes.append("mutator skipped: %s" % first_line(result[2] or result[1]))
        return None
    if result[0] not in (0, 3):
        notes.append("mutator failed: %s" % first_line(result[2] or result[1]))
        return None
    return mutator_rows(parse_mutator_snapshots(files))


def existing_run_dirs():
    return {name: os.path.exists(name) for name in RUN_DIRS}


def remove_created_dirs(existed):
    """Remove the RUN_DIRS the run created. target stays while mutator backup copies of source files are in it."""
    keep_target = mutator_backups_left()
    for name in RUN_DIRS:
        if existed[name] or not os.path.isdir(name) or (name == "target" and keep_target):
            continue
        shutil.rmtree(name, ignore_errors=True)


@contextlib.contextmanager
def run_dirs_cleaned():
    """Record the RUN_DIRS on entry and remove the ones the block created on exit, also after an exception."""
    existed = existing_run_dirs()
    try:
        yield
    finally:
        remove_created_dirs(existed)
