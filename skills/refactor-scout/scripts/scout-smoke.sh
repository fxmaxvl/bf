#!/usr/bin/env bash
# Smoke test for scout.sh. A fake HOME holds stub tools, so the run installs nothing and never touches the
# real ~/.bf. Run with bash and macOS /bin/bash.
#
# Usage: scout-smoke.sh
# Output: one PASS/FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -uo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scout=$dir/scout.sh
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

export STUB_LOG=$T/calls.log STUB_DIR=$T/stub-out
P=$T/proj
WEIRD="src/we ird (x) 'q'"

commit() { git -C "$P" add -A && git -C "$P" -c user.email=s@s -c user.name=s commit -qm "$1"; }
old_commit() { GIT_AUTHOR_DATE="2020-01-01T12:00:00" GIT_COMMITTER_DATE="2020-01-01T12:00:00" commit "$1"; }

reset() {
  rm -rf "$T/home" "$P" "$STUB_DIR"; mkdir -p "$T/home" "$P/src" "$STUB_DIR"
  : > "$STUB_LOG"
  unset STUB_DRYER_OUT STUB_MUTATOR_EDN STUB_MUTATOR_RC STUB_CRAPPER_SLEEP SCOUT_BUDGET_S
  git -C "$P" init -q
  printf 'def cold(x):\n    return x\n' > "$P/src/cold.py"
  old_commit "old"
  printf 'def hot(x):\n    return x\n' > "$P/src/hot.py"
  commit "hot 1"; echo "# 2" >> "$P/src/hot.py"; commit "hot 2"; echo "# 3" >> "$P/src/hot.py"; commit "hot 3"
}

# A ready tool: launcher and .venv python. crapper prints $STUB_DIR/<basename>.txt for the file it is given.
install_tool() {
  local n=$1 u d
  u=$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')
  d=$T/home/.bf/tools/$n
  mkdir -p "$d/.venv/bin"
  cat > "$d/$n" <<STUB
#!/bin/bash
printf '%s' "$n" >> "\$STUB_LOG"; for a in "\$@"; do printf '|%s' "\$a" >> "\$STUB_LOG"; done; echo >> "\$STUB_LOG"
[ -n "\${STUB_${u}_SLEEP:-}" ] && sleep "\$STUB_${u}_SLEEP"
mkdir -p .metrics
if [ "$n" = crapper ]; then last="\${@: -1}"; f="\$STUB_DIR/\$(basename "\$last").txt"; [ -f "\$f" ] && cat "\$f"; fi
[ "$n" = dryer ] && [ -n "\${STUB_DRYER_OUT:-}" ] && cat "\$STUB_DRYER_OUT"
[ -n "\${STUB_${u}_EDN:-}" ] && { mkdir -p .metrics/mutate; cp "\$STUB_${u}_EDN" .metrics/mutate/snap.edn; }
exit "\${STUB_${u}_RC:-0}"
STUB
  printf '#!/bin/bash\n' > "$d/.venv/bin/python"; : > "$d/.venv/.bf-installed"
  chmod +x "$d/$n" "$d/.venv/bin/python"
}

crap_out() {
  local file=$1; shift
  { printf 'CRAP Report\n===========\n\nFunction  Namespace  CC  Cov%%  CRAP\n----------------\n'
    for row in "$@"; do set -- $row; printf '%s  demo.x  %s  N/A  N/A\n' "$1" "$2"; done; } > "$STUB_DIR/$file.txt"
}

scan() { printf '%s' "${SCOPE:-}" > "$T/args.txt"; (cd "$P" && HOME="$T/home" "${BASH:-bash}" "$scout" scan "$@" < "$T/args.txt"); }
sub() { (cd "$P" && HOME="$T/home" "${BASH:-bash}" "$scout" "$@" < /dev/null); }
calls() { cat "$STUB_LOG"; }

reset
out=$(scan)
expect "no tools makes the scope not applicable" "$(jq -r .applicable <<<"$out")" "false"
has "the reason points to /bf:setup" "$out" "Run /bf:setup"

reset; install_tool crapper; install_tool dryer
mkdir -p "$P/svc"; printf 'object A\n' > "$P/svc/A.scala"; commit "scala"
out=$(SCOPE=svc scan)
expect "a Scala-only scope is not applicable" "$(jq -r .applicable <<<"$out")" "false"
has "the reason names what it found" "$out" "found 1 .scala"
expect "a scope no tool reads calls no tool" "$(calls)" ""

reset; install_tool crapper; install_tool dryer
mkdir -p "$P/web"; printf 'function a() {}\n' > "$P/web/a.js"; commit "js"
out=$(SCOPE=web scan --only dryer)
expect "--only dryer on JavaScript is not applicable" "$(jq -r .applicable <<<"$out")" "false"
out=$(SCOPE=web scan)
expect "the default run measures JavaScript with crapper" "$(jq -r .tools.crapper.measured <<<"$out")" "1"
expect "dryer reports that it reads no JavaScript" "$(jq -r .tools.dryer.state <<<"$out")" "no_files"

reset; install_tool crapper; install_tool dryer
printf 'object A\n' > "$P/src/A.scala"; commit "mixed"
crap_out hot.py "hot 12"; crap_out cold.py "cold 15"
out=$(scan)
expect "a mixed scope is applicable" "$(jq -r .applicable <<<"$out")" "true"
expect "the skipped share is counted per tool" "$(jq -r '.tools.crapper.skipped[".scala"]' <<<"$out")" "1"
lacks "every crapper call passes a coverage flag" "$(grep '^crapper' "$STUB_LOG" | grep -vE '\|--(no-coverage|use-existing-coverage)\|')" "crapper"
run=$(jq -r .run <<<"$out"); data=$P/.bf/refactor-scout/$run/candidates.json
expect "churn ranks the changed function first" "$(jq -r '.groups.crapper[0].function' "$data")" "hot"
expect "a function untouched for 6 months is stable" "$(jq -r '.groups.crapper[] | select(.function == "cold") | .stable' "$data")" "true"
has "the report has a stable section" "$(cat "$P/.bf/refactor-scout/$run/report.md")" "Stable, low priority"
expect "latest names the run" "$(cat "$P/.bf/refactor-scout/latest")" "$run"
[ ! -e "$P/.metrics" ] && ok "the .metrics the run created is removed" || bad "the .metrics the run created is removed"
lacks "mutator does not run without --mutate" "$(calls)" "mutator"

expect "show finds an id in the latest run" "$(sub show c1 | jq -r .candidate.function)" "hot"
expect "show takes run/id" "$(sub show "$run/C1" | jq -r .run)" "$run"
expect "an unknown id is an error" "$(sub show C99 | jq -r .error)" "unknown_id"

crap_out hot.py "hot 4"
expect "check passes when the function drops under the limit" "$(sub check C1 | jq -r .verdict)" "PASS"
crap_out hot.py "hot 12"
expect "check fails while the function stays over the limit" "$(sub check C1 | jq -r .verdict)" "FAIL"
crap_out hot.py "hot 4"; printf 'def split_out(x):\n    return x\n' > "$P/src/moved.py"; crap_out moved.py "split_out 14"
res=$(sub check C1)
expect "check fails when the code moves into a new file over the limit" "$(jq -r .verdict <<<"$res")" "FAIL"
has "the new function is named" "$res" "src/moved.py::split_out"
expect "each check is logged" "$(wc -l < "$P/.bf/refactor-scout/$run/checks.jsonl" | tr -d ' ')" "3"

reset; install_tool crapper
rm -rf "$P/.git"; git -C "$P" init -q
printf 'def cold(x):\n    return x\n' > "$P/src/cold.py"; printf 'def hot(x):\n    return x\n' > "$P/src/hot.py"
GIT_AUTHOR_DATE="2019-01-01T00:00:00" GIT_COMMITTER_DATE="2019-01-01T00:00:00" commit "old"
for n in 1 2; do echo "# $n" >> "$P/src/hot.py"; old_commit "hot $n"; done
crap_out hot.py "hot 12"; crap_out cold.py "cold 15"
out=$(scan --only crapper)
data=$P/.bf/refactor-scout/$(jq -r .run <<<"$out")/candidates.json
expect "in a dormant repo the window ends at the last commit" "$(jq -r '.groups.crapper[] | select(.function == "hot") | .stable' "$data")" "false"
expect "the window is stored with the run" "$(jq -r '.churn_window[1]' "$data")" "2020-01-01"

reset; install_tool crapper; install_tool dryer
for f in a b c; do printf 'def %s_total(x):\n    return x\n' "$f" > "$P/src/$f.py"; done; printf 'def shared_util(x):\n    return x\n' > "$P/src/util.py"; commit "dups"
printf 'DUPLICATE score=0.91\n  src/a.py:1-2\n  src/b.py:1-2\n\nDUPLICATE score=0.88\n  src/b.py:1-2\n  src/c.py:1-2\n' > "$T/dry.txt"
out=$(STUB_DRYER_OUT=$T/dry.txt scan --only dryer)
run=$(jq -r .run <<<"$out"); data=$P/.bf/refactor-scout/$run/candidates.json
expect "chained pairs form one cluster" "$(jq -r '.groups.dryer | length' "$data")" "1"
expect "the cluster has three members" "$(jq -r '.groups.dryer[0].members | length' "$data")" "3"
expect "a span is named by its function" "$(jq -r '.groups.dryer[0].members[0].function' "$data")" "a_total"
lacks "--only dryer runs no crapper" "$(calls)" "crapper"
expect "check fails while the pairs remain" "$(STUB_DRYER_OUT=$T/dry.txt sub check D1 | jq -r .verdict)" "FAIL"
: > "$T/none.txt"; printf 'from a import a_total\n' > "$P/src/b.py"
res=$(STUB_DRYER_OUT=$T/none.txt sub check D1)
expect "check passes when the pairs are gone" "$(jq -r .verdict <<<"$res")" "PASS"
expect "no pair of the cluster remains" "$(jq -r .after.cluster_pairs <<<"$res")" "0"
: > "$STUB_LOG"
printf 'DUPLICATE score=0.90\n  src/b.py:1-2\n  src/util.py:1-2\n' > "$T/copy.txt"
printf 'def shared_copy(x):\n    return x\n' > "$P/src/b.py"
expect "check fails when the fix copies an untouched file elsewhere in the scope" "$(STUB_DRYER_OUT=$T/copy.txt sub check D1 | jq -r .verdict)" "FAIL"
has "check passes the untouched files of the scope to dryer" "$(calls)" "|src/util.py"

reset; install_tool crapper; install_tool dryer
mkdir -p "$P/$WEIRD"; printf 'def odd(x):\n    return x\n' > "$P/$WEIRD/#lead.py"; commit "weird"
out=$(SCOPE="$WEIRD" scan --only crapper)
has "a path with a space, parentheses, a quote and a leading # reaches crapper as one argument" "$(calls)" "|$WEIRD/#lead.py"
out=$(SCOPE="nope/missing" scan)
expect "a missing scope path is an error" "$(jq -r .error <<<"$out")" "missing_path"

reset; install_tool crapper; install_tool mutator
printf '{:source "src/hot.py" :forms [{:id "demo/hot" :file "src/hot.py" :line 1 :survived 2}]}\n' > "$T/snap.edn"
out=$(STUB_MUTATOR_EDN=$T/snap.edn STUB_MUTATOR_RC=3 SCOPE=src/hot.py scan --only crapper --mutate)
data=$P/.bf/refactor-scout/$(jq -r .run <<<"$out")/candidates.json
expect "--mutate runs mutator once" "$(grep -c '^mutator' "$STUB_LOG")" "1"
expect "surviving mutants become a candidate" "$(jq -r '.groups.mutator[0].survived' "$data")" "2"
printf '{:source "src/hot.py" :forms [{:id "demo/hot" :file "src/hot.py" :line 1 :survived 0}]}\n' > "$T/snap0.edn"
expect "check on a mutator candidate fails while mutants survive" "$(STUB_MUTATOR_EDN=$T/snap.edn STUB_MUTATOR_RC=3 sub check M1 | jq -r .verdict)" "FAIL"
expect "check on a mutator candidate passes when none survive" "$(STUB_MUTATOR_EDN=$T/snap0.edn STUB_MUTATOR_RC=3 sub check M1 | jq -r .verdict)" "PASS"
res=$(STUB_MUTATOR_RC=2 sub check M1)
expect "a skipped mutator run gives UNKNOWN" "$(jq -r .verdict <<<"$res")" "UNKNOWN"
has "the skip reason is a note" "$res" "mutator skipped"
rm "$P/src/hot.py"
res=$(sub check M1)
expect "a candidate file that is gone gives UNKNOWN" "$(jq -r .verdict <<<"$res")" "UNKNOWN"
has "the reason says the file is gone" "$res" "the file is gone"

reset; install_tool crapper
expect "show before any scan is no_runs" "$(sub show C1 | jq -r .error)" "no_runs"
expect "show of a missing run is unknown_run" "$(sub show nope/C1 | jq -r .error)" "unknown_run"
expect "an unknown scan flag is bad_args" "$(scan --bogus | jq -r .error)" "bad_args"
expect "show without an id is bad_args" "$(sub show | jq -r .error)" "bad_args"
expect "check with two ids is bad_args" "$(sub check C1 C2 | jq -r .error)" "bad_args"
expect "a scope outside the repository is outside_repo" "$(SCOPE=$T scan | jq -r .error)" "outside_repo"
mkdir -p "$T/plain"
expect "a directory outside git is not_a_git_repo" "$(cd "$T/plain" && HOME="$T/home" "${BASH:-bash}" "$scout" scan < /dev/null | jq -r .error)" "not_a_git_repo"
rm -rf "$P/.git"; git -C "$P" init -q
expect "a repository without a commit is no_commits" "$(scan | jq -r .error)" "no_commits"

reset; install_tool crapper
crap_out hot.py "hot 12"
scan --only crapper > /dev/null
rm -rf "$T/home/.bf/tools/crapper"
expect "check without the tool is tool_missing" "$(sub check C1 | jq -r .error)" "tool_missing"

reset; install_tool crapper
crap_out hot.py "hot 12"
git clone -q --depth 1 "file://$P" "$T/shallow"
has "a shallow clone gives a note" "$(P=$T/shallow scan --only crapper)" "The clone is shallow"
rm -rf "$T/shallow"

reset; install_tool crapper
printf 'def fresh(x):\n    return x\n' > "$P/src/fresh.py"; echo "# edit" >> "$P/src/cold.py"
crap_out fresh.py "fresh 14"; crap_out cold.py "cold 15"
out=$(scan --only crapper)
run=$(jq -r .run <<<"$out"); data=$P/.bf/refactor-scout/$run/candidates.json
expect "an untracked file is active, not stable" "$(jq -r '.groups.crapper[] | select(.function == "fresh") | .stable' "$data")" "false"
expect "a file changed against HEAD is active, not stable" "$(jq -r '.groups.crapper[] | select(.function == "cold") | .stable' "$data")" "false"
has "the report says so" "$(cat "$P/.bf/refactor-scout/$run/report.md")" "untracked or changed against HEAD"

reset; install_tool crapper
out=$(SCOUT_BUDGET_S=2 STUB_CRAPPER_SLEEP=20 scan --only crapper)
has "a tool past the budget gives a note" "$out" "crapper hit its time limit"

unit=$(python3 -I "$dir/scout-unit.py" 2>&1); unit_rc=$?
while IFS= read -r line; do
  case "$line" in PASS*) ok "${line#PASS }" ;; FAIL*) bad "${line#FAIL }" ;; esac
done <<<"$unit"
[ "$unit_rc" -eq 0 ] && ok "scout-unit.py exits 0" || bad "scout-unit.py exits 0"

grep -q 'BUDGET_S = int(os.environ.get("SCOUT_BUDGET_S", "480"))' "$dir/scout.py" && ok "the default budget is 480 s" || bad "the default budget is 480 s"
grep -q 'timeout: 600000' "$dir/../SKILL.md" && ok "SKILL.md passes timeout 600000" || bad "SKILL.md passes timeout 600000"

echo "---- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
