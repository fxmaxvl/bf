"""Unit cases for the pure functions of scout.py and measured_tools.py. scout-smoke.sh runs this file."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["MEASURED_TOOLS_DIR"] = os.path.join(HERE, "..", "..", "feature", "scripts")
os.environ["SETUP_SH"] = "unused"
sys.dont_write_bytecode = True
sys.path.insert(0, os.environ["MEASURED_TOOLS_DIR"])
sys.path.insert(0, HERE)
import measured_tools as mt  # noqa: E402
import scout  # noqa: E402

failed = 0


def check(name, got, want):
    global failed
    if got == want:
        print("PASS unit: " + name)
    else:
        failed += 1
        print("FAIL unit: %s: got %r, want %r" % (name, got, want))


def side(file_, function):
    return {"file": file_, "function": function, "start": 1, "end": 2}


def pair(a, b, score):
    return {"a": side(*a), "b": side(*b), "score": score}


CRAPPER_OUT = """CRAP Report
===========

Function  Namespace  CC  Cov%  CRAP
----------------
hot  demo.x  12  N/A  N/A
tidy  demo.x  3  80.5%  3.4
bad  demo.x  x  N/A  N/A
short  1
"""
check("parse_crapper reads rows after the rule", mt.parse_crapper(CRAPPER_OUT),
      [("hot", 12, None, None), ("tidy", 3, 80.5, 3.4)])
check("parse_crapper ignores text before the rule", mt.parse_crapper("hot  demo.x  12  N/A  N/A\n"), [])

DRYER_OUT = "DUPLICATE score=0.91\n  a.py:1-2\n  b.py:3-4\n\nDUPLICATE score=0.88\n  c.py:1-2\n"
check("parse_dryer keeps a complete pair and drops a half pair", mt.parse_dryer(DRYER_OUT),
      [("0.91", ("a.py", "1", "2"), ("b.py", "3", "4"))])

check("pair_key is the same for either side order",
      scout.pair_key(pair(("a.py", "f"), ("b.py", "g"), 1.0)), scout.pair_key(pair(("b.py", "g"), ("a.py", "f"), 1.0)))
check("pair_key sorts the two keys", scout.pair_key(pair(("b.py", "g"), ("a.py", "f"), 1.0)),
      ("a.py::f", "b.py::g"))

chain = [pair(("a.py", "f"), ("b.py", "g"), 0.91), pair(("b.py", "g"), ("c.py", "h"), 0.88)]
found = scout.clusters(chain)
check("clusters merges chained pairs into one", len(found), 1)
check("a cluster holds each member once", len(found[0]["members"]), 3)
check("a cluster scores its closest pair", found[0]["score"], 0.91)
apart = [pair(("a.py", "f"), ("b.py", "g"), 0.9), pair(("c.py", "h"), ("d.py", "i"), 0.8)]
check("clusters keeps unrelated pairs apart", len(scout.clusters(apart)), 2)
same_files = [pair(("a.py", "f"), ("b.py", "g"), 0.9), pair(("a.py", "f2"), ("b.py", "g2"), 0.85)]
check("clusters over the same files merge", len(scout.clusters(same_files)), 1)


def cand(churn, score):
    return {"churn": churn, "score": score, "function": "fn"}


notes = []
ranked = scout.order([cand(0, 99), cand(2, 10), cand(5, 10)], "crapper", notes)
check("order puts the highest score times churn first", [c["churn"] for c in ranked], [5, 2, 0])
check("order numbers ids with the tool prefix", [c["id"] for c in ranked], ["C1", "C2", "C3"])
check("order marks zero churn as stable", [c["stable"] for c in ranked], [False, False, True])
check("order writes the done_when line", ranked[0]["done_when"].startswith("`fn` and every function"), True)
check("a dryer id has the D prefix", scout.order([cand(1, 1)], "dryer", [])[0]["id"], "D1")
many = [cand(1, i) for i in range(scout.MAX_PER_GROUP + 3)]
notes = []
check("order keeps at most MAX_PER_GROUP", len(scout.order(many, "mutator", notes)), scout.MAX_PER_GROUP)
check("order says it cut the list", len(notes), 1)
check("done_when without a candidate names the group generically",
      scout.done_when("mutator"), "0 mutants survive in the function.")

with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "m.py")
    with open(path, "w") as handle:
        handle.write("x = 1\n@decorator\ndef target(a):\n    return a\nvalue = helper(2)\n")
    check("span_name skips a decorator and reads the declaration", scout.span_name(path, 2), "target")
    check("span_name falls back to a call", scout.span_name(path, 5), "helper")
    plain = os.path.join(tmp, "plain.py")
    with open(plain, "w") as handle:
        handle.write("x = 1\ny = 2\nz = 3\n")
    check("span_name falls back to the line number", scout.span_name(plain, 1), "line 1")
    check("span_name on a missing file names the line", scout.span_name(os.path.join(tmp, "none.py"), 7), "line 7")

    snapshot = os.path.join(tmp, ".metrics", "mutate")
    os.makedirs(snapshot)
    with open(os.path.join(snapshot, "s.edn"), "w") as handle:
        handle.write('{:source "src/a.py" :forms [{:id "demo/hot" :file "src/a.py" :line 4 :survived 2} '
                     '{:id "demo/cold" :line 9 :survived 0}]}\n')
    here = os.getcwd()
    os.chdir(tmp)
    try:
        check("parse_mutator_snapshots keeps forms with survivors", mt.parse_mutator_snapshots(["src/a.py"]),
              [("src/a.py", 4, 2, "hot")])
        check("parse_mutator_snapshots skips other sources", mt.parse_mutator_snapshots(["src/b.py"]), [])
    finally:
        os.chdir(here)

check("coverage_flag without a report", mt.coverage_flag(False), "--no-coverage")
check("crapper_rows keeps only rows at the limit", [r["function"] for r in mt.crapper_rows("f.py", mt.NO_COVERAGE, CRAPPER_OUT)], ["hot"])

print("---- unit: %d failed" % failed)
sys.exit(1 if failed else 0)
