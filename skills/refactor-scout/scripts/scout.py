"""scan, show and check for bf:refactor-scout. scout.sh documents the interface, so run this file through scout.sh."""
import collections
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.environ["MEASURED_TOOLS_DIR"])
from measured_tools import (CRAP_LIMIT, DRY_THRESHOLD, TOOL_EXTS, check_tools, coverage_flag,  # noqa: E402
                            has_report, mutator_mode, run_crapper, run_dirs_cleaned, run_dryer, run_mutator)

BUDGET_S = int(os.environ.get("SCOUT_BUDGET_S", "480"))  # the override is test-only
CRAPPER_FILE_S = 60
DRYER_S = 120
CHURN_S = 45  # one deadline for file churn and function churn together
CHURN_DAYS = 182
FUNCTION_CHURN_TOP = 15
FUNCTION_CHURN_S = 10
SPAN_NAME_LINES = 3
ACTIVE_SHOWN = 5
DRYER_NAMES_SHOWN = 4
MAX_PER_GROUP = 50
DEFAULT_TOOLS = ["crapper", "dryer"]
PREFIX = {"crapper": "C", "dryer": "D", "mutator": "M"}
# The directories and test files crapper skips (crapper --help). Scout skips them for every tool.
SKIP_DIRS = {".clj-kondo", ".git", ".hg", ".idea", ".metrics", ".svn", ".venv", "__pycache__", "__tests__", "build",
             "coverage", "dist", "node_modules", "out", "spec", "specs", "target", "test", "testdata", "tests",
             "vendor", "venv", ".bf"}
TEST_FILE = re.compile(r"(_test\.(go|clj|cljc|cljs|bb|py)|\.(test|spec)\.(ts|tsx|mts|cts|js|jsx|mjs|cjs))$"
                       r"|^test_.*\.py$|^conftest\.py$")
# Source files no tool reads still count, so the report can say what share of the scope it skipped.
SOURCE_EXTS = set().union(*TOOL_EXTS.values()) | {
    ".scala", ".sc", ".kt", ".kts", ".groovy", ".rb", ".php", ".cs", ".fs", ".swift", ".m", ".mm", ".c", ".h",
    ".cc", ".cpp", ".hpp", ".dart", ".lua", ".ex", ".exs", ".erl", ".hs", ".ml", ".r", ".jl", ".pl", ".sh"}
DECLARED = re.compile(r"\b(?:def|defn-?|fn|func|function|fun)\s+(?:\([^)]*\)\s*)?([A-Za-z_$][\w$?!*<>-]*)")
CALLED = re.compile(r"([A-Za-z_$][\w$]*)\s*(?:=\s*(?:async\s*)?(?:function\b|\()|\()")
KEYWORDS = {"if", "for", "while", "switch", "catch", "return", "new", "await", "async", "function"}


def emit(obj):
    sys.stdout.write(json.dumps(obj, indent=1) + "\n")


def fail(code, detail):
    emit({"error": code, "detail": detail})
    sys.exit(1)


def git(*args, timeout=None):
    try:
        done = subprocess.run(["git", "--literal-pathspecs"] + list(args), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, ""
    return done.returncode, done.stdout


def repo_root():
    code, out = git("rev-parse", "--show-toplevel")
    if code != 0:
        fail("not_a_git_repo", "run inside a git repository")
    return out.strip()


def skipped(path):
    parts = path.split("/")
    return any(part in SKIP_DIRS for part in parts[:-1]) or bool(TEST_FILE.search(parts[-1]))


def read_scope(root):
    scope = []
    for line in sys.stdin.read().splitlines():
        line = line.rstrip("\r")
        if not line.strip():
            continue
        full = os.path.abspath(line)
        if not os.path.exists(full):
            fail("missing_path", "no such path: %s" % line)
        rel = os.path.relpath(full, root)
        if rel == ".." or rel.startswith("../"):
            fail("outside_repo", "%s is outside %s" % (line, root))
        scope.append(rel)
    return scope or ["."]


def list_files(scope):
    code, out = git("ls-files", "-z", "-co", "--exclude-standard", "--", *scope)
    if code != 0:
        fail("ls_files_failed", "git ls-files failed for the scope")
    return sorted({p for p in out.split("\0") if p and os.path.isfile(p) and not skipped(p)})


def ext(path):
    return os.path.splitext(path)[1]


def tool_files(tool, files):
    return [f for f in files if ext(f) in TOOL_EXTS[tool]]


def tool_rev(path):
    code, out = git("-C", os.path.dirname(path), "rev-parse", "--short", "HEAD")
    return out.strip() if code == 0 else "unknown"


def tool_status(tools, files, ready):
    status = {}
    for tool in tools:
        measured = tool_files(tool, files)
        others = collections.Counter(ext(f) for f in files if ext(f) in SOURCE_EXTS and ext(f) not in TOOL_EXTS[tool])
        state = "not_installed" if tool not in ready else ("no_files" if not measured else "ready")
        status[tool] = {"state": state, "measured": len(measured), "skipped": dict(others.most_common()),
                        "rev": tool_rev(ready[tool]) if tool in ready else None}
    return status


def why_not(tool, entry):
    if entry["state"] == "not_installed":
        return "%s is not installed. Run /bf:setup." % tool
    found = ", ".join("%d %s" % (n, e) for e, n in entry["skipped"].items()) or "no source files"
    return "%s reads none of the files in scope (found %s)." % (tool, found)


def span_name(path, start):
    """The function a dryer span starts. dryer prints lines, and check matches spans by name across edits."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()[start - 1:start - 1 + SPAN_NAME_LINES]
    except OSError:
        return "line %d" % start
    for line in lines:
        if line.lstrip().startswith("@"):
            continue
        match = DECLARED.search(line)
        if match:
            return match.group(1)
        for match in CALLED.finditer(line):
            if match.group(1) not in KEYWORDS:
                return match.group(1)
    return "line %d" % start


def key(file_, name):
    return "%s::%s" % (file_, name)


def score_crapper(path, files, mode_for, deadline, notes):
    return run_crapper(path, files, mode_for, lambda: min(CRAPPER_FILE_S, deadline - time.time()), notes)


def dryer_pairs(path, files, deadline, notes):
    pairs = []
    for row in run_dryer(path, files, lambda: min(DRYER_S, deadline - time.time()), notes):
        sides = [dict(span, function=span_name(span["file"], span["start"])) for span in (row["a"], row["b"])]
        pairs.append({"a": sides[0], "b": sides[1], "score": row["score"]})
    return pairs


def pair_key(pair):
    return tuple(sorted((key(pair["a"]["file"], pair["a"]["function"]), key(pair["b"]["file"], pair["b"]["function"]))))


def clusters(pairs):
    parent = {}

    def find(k):
        parent.setdefault(k, k)
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for pair in pairs:
        a, b = pair_key(pair)
        parent[find(a)] = find(b)
    grouped = collections.OrderedDict()
    for pair in pairs:
        root = find(pair_key(pair)[0])
        entry = grouped.setdefault(root, {"members": collections.OrderedDict(), "pairs": []})
        for side in (pair["a"], pair["b"]):
            entry["members"].setdefault(key(side["file"], side["function"]), side)
        entry["pairs"].append(pair)
    # Clusters over the same files merge: seven copied functions between a.py and b.py are one refactor.
    by_files = collections.OrderedDict()
    for entry in grouped.values():
        members = list(entry["members"].values())
        merged = by_files.setdefault(frozenset(m["file"] for m in members), {"members": [], "pairs": []})
        merged["members"] += members
        merged["pairs"] += entry["pairs"]
    return [dict(e, score=max(p["score"] for p in e["pairs"])) for e in by_files.values()]


def churn_since():
    """The window ends at the last commit, not today, so a repo nobody touched lately still ranks by its last active months."""
    code, out = git("log", "-1", "--format=%ct", "HEAD")
    end = int(out.strip()) if code == 0 and out.strip().isdigit() else int(time.time())
    return time.strftime("%Y-%m-%d", time.gmtime(end - CHURN_DAYS * 86400)), time.strftime("%Y-%m-%d", time.gmtime(end))


def file_churn(scope, since, deadline, notes):
    code, out = git("log", "--since=" + since, "--format=", "--name-only", "--", *scope,
                    timeout=max(1, deadline - time.time()))
    if code != 0:
        notes.append("git log failed or timed out, churn is 0 everywhere.")
        return collections.Counter()
    return collections.Counter(line for line in out.splitlines() if line)


def function_churn(name, file_, since, deadline):
    limit = deadline - time.time()
    if limit <= 1 or name.startswith("line ") or ":" in name:
        return None
    # git reads the name as a basic regex, where + ? ( | { are literal and need no escape.
    pattern = re.sub(r"([.\[\]*^$\\])", r"\\\1", name)
    code, out = git("log", "-s", "--since=" + since, "--format=%H", "-L", ":%s:%s" % (pattern, file_),
                    timeout=min(FUNCTION_CHURN_S, limit))
    if code != 0:
        return None
    return sum(1 for line in out.splitlines() if re.match(r"^[0-9a-f]{40}$", line))


def add_function_churn(rows, churn, since, deadline, uncommitted):
    """A file untracked or changed against HEAD has a change git log cannot see, so its rows never fall below 1."""
    for rank, row in enumerate(sorted(rows, key=lambda r: -r["score"])):
        counted = function_churn(row["function"], row["file"], since, deadline) if rank < FUNCTION_CHURN_TOP else None
        row["churn"], row["churn_level"] = (counted, "function") if counted is not None else (churn[row["file"]], "file")
        if row["file"] in uncommitted:
            row["churn"] = max(row["churn"], 1)


DONE_TEMPLATES = {
    "crapper": "%(subject)s and every function that replaces it score under %(crap)d, and no other function in the "
               "touched files reaches %(crap)d.",
    "dryer": "no pair in %(subject)s scores %(dry).2f or more, and no new pair at %(dry).2f or more links a touched "
             "file to any file in the scanned scope.",
    "mutator": "0 mutants survive in %(subject)s.",
}
GENERIC_SUBJECT = {"crapper": "the function", "dryer": "the cluster", "mutator": "the function"}


def done_when(group, cand=None):
    """The finish line for one candidate, or for any candidate of the group when cand is None."""
    if cand is None:
        subject = GENERIC_SUBJECT[group]
    else:
        subject = "this cluster" if group == "dryer" else "`%s`" % cand["function"]
    return DONE_TEMPLATES[group] % {"subject": subject, "crap": CRAP_LIMIT, "dry": float(DRY_THRESHOLD)}


def order(cands, tool, notes):
    active = sorted([c for c in cands if c["churn"] > 0], key=lambda c: -(c["score"] * c["churn"]))
    stable = sorted([c for c in cands if c["churn"] == 0], key=lambda c: -c["score"])
    ranked = active + stable
    if len(ranked) > MAX_PER_GROUP:
        notes.append("%s found %d candidates, the run keeps the first %d." % (tool, len(ranked), MAX_PER_GROUP))
        ranked = ranked[:MAX_PER_GROUP]
    for n, cand in enumerate(ranked, 1):
        cand["id"] = "%s%d" % (PREFIX[tool], n)
        cand["stable"] = cand["churn"] == 0
        cand["group"] = tool
        cand["done_when"] = done_when(tool, cand)
    return ranked


def runs_dir(root):
    return os.path.join(root, ".bf", "refactor-scout")


def new_run_dir(root):
    base = runs_dir(root)
    os.makedirs(base, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%S")
    name, n = stamp, 2
    while True:
        try:
            os.mkdir(os.path.join(base, name))
            return base, name
        except FileExistsError:
            name, n = "%s-%d" % (stamp, n), n + 1


def parse_scan_args(argv):
    only, mutate = None, False
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--mutate":
            mutate = True
        elif arg == "--only" and args and args[0] in ("crapper", "dryer"):
            only = args.pop(0)
        else:
            fail("bad_args", "scan takes [--only crapper|dryer] [--mutate], got %s" % arg)
    return only, mutate


def run_tools(ready, runnable, files, deadline, notes):
    """Run each runnable tool on the files it reads. Returns the candidate rows per tool."""
    results = {}
    with run_dirs_cleaned():
        if "crapper" in runnable:
            reserve = (DRYER_S if "dryer" in runnable else 0) + (BUDGET_S // 3 if "mutator" in runnable else 0)
            results["crapper"] = score_crapper(ready["crapper"], tool_files("crapper", files),
                                               lambda f: coverage_flag(has_report(f)), deadline - reserve, notes)
        if "dryer" in runnable:
            results["dryer"] = dryer_pairs(ready["dryer"], tool_files("dryer", files), deadline, notes)
        if "mutator" in runnable:
            measured = tool_files("mutator", files)
            mode = mutator_mode(measured)
            survivors = run_mutator(ready["mutator"], measured, mode, lambda: deadline - time.time(), notes)
            results["mutator"] = [dict(s, mode=mode) for s in survivors or []]
    return results


def rank_groups(results, churn, since, uncommitted, churn_deadline, notes):
    groups = {}
    if "crapper" in results:
        add_function_churn(results["crapper"], churn, since, churn_deadline, uncommitted)
        groups["crapper"] = order(results["crapper"], "crapper", notes)
    if "dryer" in results:
        cands = clusters(results["dryer"])
        for cand in cands:
            cand["churn"] = sum(churn[f] for f in {m["file"] for m in cand["members"]})
            cand["churn_level"] = "file"
        groups["dryer"] = order(cands, "dryer", notes)
    if "mutator" in results:
        add_function_churn(results["mutator"], churn, since, churn_deadline, uncommitted)
        groups["mutator"] = order(results["mutator"], "mutator", notes)
    return groups


def write_run(root, data):
    """Write candidates.json, report.md and the latest pointer. Returns the report path."""
    base, run = new_run_dir(root)
    data["run"] = run
    with open(os.path.join(base, run, "candidates.json"), "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=1)
    report = os.path.join(base, run, "report.md")
    with open(report, "w", encoding="utf-8") as handle:
        handle.write(render(data))
    with open(os.path.join(base, "latest"), "w", encoding="utf-8") as handle:
        handle.write(run + "\n")
    return report


def scan(argv):
    only, mutate = parse_scan_args(argv)
    root = repo_root()
    scope = read_scope(root)
    os.chdir(root)
    code, head = git("rev-parse", "HEAD")
    if code != 0:
        fail("no_commits", "the repository has no commit to measure against")
    files = list_files(scope)
    tools = ([only] if only else list(DEFAULT_TOOLS)) + (["mutator"] if mutate else [])
    ready, error = check_tools(os.environ["SETUP_SH"], tools)
    if error:
        emit({"applicable": False, "reason": "The tool check failed: %s. Run /bf:setup." % error})
        return
    status = tool_status(tools, files, ready)
    runnable = [t for t in tools if status[t]["state"] == "ready"]
    if not runnable:
        emit({"applicable": False, "reason": " ".join(why_not(t, status[t]) for t in tools), "tools": status})
        return

    notes = []
    if git("rev-parse", "--is-shallow-repository")[1].strip() == "true":
        notes.append("The clone is shallow, so churn misses older commits and more candidates look stable.")
    started = time.time()
    results = run_tools(ready, runnable, files, started + BUDGET_S, notes)

    since, until = churn_since()
    churn_deadline = time.time() + CHURN_S
    churn = file_churn(scope, since, churn_deadline, notes)
    uncommitted = changed_files("HEAD") & set(files)
    for f in uncommitted:
        churn[f] += 1
    if uncommitted:
        notes.append("%d files in scope are untracked or changed against HEAD. They count as active, not stable."
                     % len(uncommitted))
    groups = rank_groups(results, churn, since, uncommitted, churn_deadline, notes)
    data = {"run": None, "created": time.strftime("%Y-%m-%d %H:%M"), "head": head.strip(), "scope": scope,
            "churn_window": [since, until], "files": files, "tools": status, "notes": notes, "seconds": round(time.time() - started),
            "crap_over": sorted(key(r["file"], r["function"]) for r in results.get("crapper", [])),
            "dry_pairs": sorted(list(pair_key(p)) for p in results.get("dryer", [])),
            "groups": groups}
    report = write_run(root, data)
    emit({"applicable": True, "run": data["run"], "report": report, "notes": notes,
          "tools": {t: {k: v for k, v in s.items() if k != "rev"} for t, s in status.items()},
          "groups": {g: {"count": len(c), "active": sum(1 for x in c if not x["stable"]),
                         "top": [x["id"] for x in c if not x["stable"]][:ACTIVE_SHOWN]} for g, c in groups.items()}})


def cell(text):
    return str(text).replace("|", "\\|")


def measured_line(tool, entry):
    if entry["state"] != "ready":
        return "- %s: not run. %s" % (tool, why_not(tool, entry))
    skipped = ", ".join("%d %s" % (n, e) for e, n in entry["skipped"].items())
    return "- %s: measured %d files.%s" % (tool, entry["measured"], " Skipped %s." % skipped if skipped else "")


def crapper_row(c):
    detail = "CRAP %.1f, CC %d, coverage %.0f%%" % (c["crap"], c["cc"], c["coverage"] or 0) if c["crap"] is not None \
        else "CC %d, no coverage" % c["cc"]
    return "| %s | `%s` in `%s` | %s | %d (%s) |" % (c["id"], cell(c["function"]), cell(c["file"]), detail,
                                                   c["churn"], c["churn_level"])


def dryer_row(c):
    paths = sorted({m["file"] for m in c["members"]})
    shared = os.path.dirname(paths[0]) if len(paths) == 1 else os.path.commonpath(paths)
    shown = [os.path.relpath(f, shared) for f in paths] if shared else paths
    files = ("`%s/` " % cell(shared) if shared else "") + ", ".join("`%s`" % cell(f) for f in shown)
    functions = list(collections.OrderedDict.fromkeys(m["function"] for m in c["members"]))
    names = "%s: %s" % (files, ", ".join("`%s`" % cell(f) for f in functions[:DRYER_NAMES_SHOWN]))
    more = " and %d more" % (len(functions) - DRYER_NAMES_SHOWN) if len(functions) > DRYER_NAMES_SHOWN else ""
    pairs = len(c["pairs"])
    return "| %s | %s%s | %.2f, %d %s | %d (file) |" % (c["id"], names, more, c["score"], pairs,
                                                       "pair" if pairs == 1 else "pairs", c["churn"])


def mutator_row(c):
    return "| %s | `%s` in `%s:%d` | %d surviving | %d (%s) |" % (c["id"], cell(c["function"]), cell(c["file"]),
                                                               c["line"], c["survived"], c["churn"], c["churn_level"])


SECTIONS = [
    ("dryer", "DRY: duplicate clusters (dryer)", "Cluster", "Score", dryer_row),
    ("crapper", "CRAP: complex functions (crapper)", "Function", "Score", crapper_row),
    ("mutator", "Mutation: weak tests (mutator)", "Function", "Mutants", mutator_row),
]


def render(data):
    out = ["# Refactoring candidates", "",
           "Run `%s`, %s, at `%s`. Scope: %s." % (data["run"], data["created"], data["head"][:10],
                                                  ", ".join("`%s`" % s for s in data["scope"])), "",
           "## Measured", ""]
    out += [measured_line(t, s) for t, s in data["tools"].items()]
    out += ["- Churn: commits from %s to %s, the 6 months before the last commit. Ranking is score × churn inside "
            "each group." % tuple(data["churn_window"])]
    out += ["- Note: %s" % n for n in data["notes"]]
    for group, title, what, score, row in SECTIONS:
        if group not in data["groups"]:
            continue
        cands = data["groups"][group]
        out += ["", "## " + title, ""]
        if not cands:
            out.append("No candidates.")
            continue
        head = ["| ID | %s | %s | Churn |" % (what, score), "|---|---|---|---|"]
        active = [c for c in cands if not c["stable"]]
        stable = [c for c in cands if c["stable"]]
        if active:
            out += head + [row(c) for c in active]
        if stable:
            out += ["", "Stable, low priority (no change in that window):", ""] + head + [row(c) for c in stable]
        out += ["", "Done when, for each candidate: " + done_when(group)]
    out += ["", "Next: `/bf:refactor-scout plan <ID>` designs options for one candidate.", ""]
    return "\n".join(out)


def load(ref):
    """Returns (root, data, cand) for a candidate id, or for run/id."""
    root = repo_root()
    base = runs_dir(root)
    if "/" in ref:
        run, cid = ref.split("/", 1)
    else:
        try:
            with open(os.path.join(base, "latest"), encoding="utf-8") as handle:
                run = handle.read().strip()
        except OSError:
            fail("no_runs", "no scan has run in this repository. Run scan first.")
        cid = ref
    try:
        with open(os.path.join(base, run, "candidates.json"), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        fail("unknown_run", "no readable run %s under %s" % (run, base))
    for cands in data["groups"].values():
        for cand in cands:
            if cand["id"].upper() == cid.upper():
                return root, data, cand
    fail("unknown_id", "run %s has no candidate %s" % (run, cid))


def show(argv):
    if len(argv) != 1:
        fail("bad_args", "show takes one candidate id")
    _, data, cand = load(argv[0])
    emit({"run": data["run"], "head": data["head"], "candidate": cand})


def changed_files(head):
    """Files changed against head in the working tree, plus untracked files, as repository-relative paths."""
    _, diffed = git("diff", "--name-only", "-z", head)
    _, untracked = git("ls-files", "-z", "-o", "--exclude-standard")
    return {p for p in (diffed + untracked).split("\0") if p}


def touched_files(head, tool):
    return sorted(p for p in changed_files(head) if os.path.isfile(p) and not skipped(p) and ext(p) in TOOL_EXTS[tool])


def existed_at(head, path):
    return git("cat-file", "-e", "%s:%s" % (head, path))[0] == 0


def new_over_limit(rows, data, cand):
    """Returns (target row or None, fresh keys, outside keys). The other functions over the limit are fresh when
    they sit in a scanned file or in a file the scan commit did not have, and outside otherwise."""
    target = key(cand["file"], cand["function"])
    excused = set(data["crap_over"]) - {target}
    scanned = set(data["files"])
    now = {key(r["file"], r["function"]): r for r in rows}
    others = {k: r for k, r in now.items() if k != target and k not in excused}
    fresh = [k for k, r in others.items() if r["file"] in scanned or not existed_at(data["head"], r["file"])]
    return now.get(target), fresh, [k for k in others if k not in fresh]


def check_crapper(path, data, cand, touched, notes):
    files = sorted(set(([cand["file"]] if os.path.isfile(cand["file"]) else []) + touched))
    if not files:
        return "UNKNOWN", {}, {"reason": "the file is gone and no changed file was found"}
    rows = score_crapper(path, files, lambda f: cand["mode"], time.time() + BUDGET_S, notes)
    after, fresh, outside = new_over_limit(rows, data, cand)
    if outside:
        notes.append("Over the limit in files outside the scan scope, not counted: %s." % ", ".join(outside))
    verdict = "PASS" if after is None and not fresh else "FAIL"
    return verdict, {"score": after["score"] if after else None, "new_over_limit": fresh}, \
        {"target": "still over the limit" if after else "under the limit or gone"}


def dryer_scope(data, cand, touched):
    """The whole scanned scope, so a new helper that copies an untouched util elsewhere still shows as a new pair."""
    scanned = {f for f in data["files"] if ext(f) in TOOL_EXTS["dryer"] and os.path.isfile(f)}
    return sorted(scanned | {m["file"] for m in cand["members"] if os.path.isfile(m["file"])} | set(touched))


def check_dryer(path, data, cand, touched, notes):
    members = {key(m["file"], m["function"]) for m in cand["members"]}
    files = dryer_scope(data, cand, touched)
    pairs = dryer_pairs(path, files, time.time() + BUDGET_S, notes) if files else []
    baseline = {tuple(p) for p in data["dry_pairs"]}
    touched_set = set(touched)
    remaining = [p for p in pairs if set(pair_key(p)) <= members]
    fresh = [p for p in pairs if pair_key(p) not in baseline
             and (p["a"]["file"] in touched_set or p["b"]["file"] in touched_set)]
    verdict = "PASS" if not remaining and not fresh else "FAIL"
    return verdict, {"cluster_pairs": len(remaining), "new_pairs": len(fresh)}, \
        {"remaining": [list(pair_key(p)) for p in remaining], "new": [list(pair_key(p)) for p in fresh]}


def check_mutator(path, data, cand, touched, notes):
    if not os.path.isfile(cand["file"]):
        return "UNKNOWN", {}, {"reason": "the file is gone"}
    deadline = time.time() + BUDGET_S
    survivors = run_mutator(path, [cand["file"]], cand["mode"], lambda: deadline - time.time(), notes)
    if survivors is None:
        return "UNKNOWN", {}, {"reason": "mutator gave no result"}
    count = sum(s["survived"] for s in survivors if s["function"] == cand["function"])
    return ("PASS" if count == 0 else "FAIL"), {"survived": count}, {}


CHECKS = {"crapper": check_crapper, "dryer": check_dryer, "mutator": check_mutator}


def check(argv):
    if len(argv) != 1:
        fail("bad_args", "check takes one candidate id")
    root, data, cand = load(argv[0])
    os.chdir(root)
    tool = cand["group"]
    notes = []
    ready, error = check_tools(os.environ["SETUP_SH"], [tool])
    if tool not in ready:
        fail("tool_missing", "%s is not installed%s. Run /bf:setup." % (tool, " (%s)" % error if error else ""))
    if git("cat-file", "-e", data["head"])[0] != 0:
        notes.append("The scan commit %s is gone, so changed files cannot be found." % data["head"][:10])
    rev = tool_rev(ready[tool])
    if rev != data["tools"][tool]["rev"]:
        notes.append("%s changed since the scan (%s, now %s). Scores can move for that reason alone."
                     % (tool, data["tools"][tool]["rev"], rev))
    touched = touched_files(data["head"], tool)
    with run_dirs_cleaned():
        verdict, after, details = CHECKS[tool](ready[tool], data, cand, touched, notes)
    before = {"score": cand["score"]} if tool != "dryer" else {"cluster_pairs": len(cand["pairs"]), "score": cand["score"]}
    result = {"run": data["run"], "id": cand["id"], "verdict": verdict, "done_when": cand["done_when"],
              "before": before, "after": after, "details": details, "touched": touched, "notes": notes}
    with open(os.path.join(runs_dir(root), data["run"], "checks.jsonl"), "a", encoding="utf-8") as handle:
        handle.write(json.dumps(dict(result, at=time.strftime("%Y-%m-%d %H:%M"))) + "\n")
    emit(result)


def main():
    modes = {"scan": scan, "show": show, "check": check}
    if len(sys.argv) < 2 or sys.argv[1] not in modes:
        fail("bad_args", "usage: scout.sh scan|show|check ...")
    modes[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
