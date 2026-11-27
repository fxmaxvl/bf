"""Run crapper, dryer and mutator and parse their output.

measured-gate.sh and refactor-scout's scout.py import this module, so each tool has one runner and one
parser. The report text each caller builds from the parsed rows stays with that caller.
"""
import glob
import json
import os
import re
import shutil
import signal
import subprocess

TOOLS = ["crapper", "dryer", "mutator"]
TERM_GRACE_S = 5
# The union of the three tools' languages. Each tool's own set is in TOOL_EXTS.
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


def mutator_backups_left():
    return any(files for _, _, files in os.walk("target/mutator-backup"))


def existing_run_dirs():
    return {name: os.path.exists(name) for name in RUN_DIRS}


def remove_created_dirs(existed):
    """Remove the RUN_DIRS the run created. target stays while mutator backup copies of source files are in it."""
    keep_target = mutator_backups_left()
    for name in RUN_DIRS:
        if existed[name] or not os.path.isdir(name) or (name == "target" and keep_target):
            continue
        shutil.rmtree(name, ignore_errors=True)
