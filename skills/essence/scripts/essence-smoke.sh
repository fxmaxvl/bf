#!/usr/bin/env bash
# Smoke check for essence-init.sh argument/path resolution and ledger-check.sh accounting.
#
# Usage: essence-smoke.sh
# Contract: exits 0 when every case passes, 1 otherwise; prints one PASS/FAIL line per case.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
init="$here/essence-init.sh"
check_ledger="$here/ledger-check.sh"
command -v jq >/dev/null || { echo "FAIL jq is required"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # name, condition-exit-status
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}
q() { jq -e "$2" <<< "$1" >/dev/null; echo $?; }

mkdir -p "$tmp/r" && cd "$tmp/r" && git init -q -b main .
printf '# My PRD\n\n## Goals\n- one\n' > "My PRD.md"
printf '\n  \n' > blank.md
printf '<!-- bf:essence source=x -->\n# done\n' > done-essence.md

out=$(bash "$init" "My PRD.md")
check "default budget is 3, slug is kebab-case" "$(q "$out" '.budget == 3 and .budget_default and .slug == "my-prd" and (.out_path | endswith(".bf/essence/my-prd-essence.md"))')"
out=$(bash "$init" My PRD.md top 2)
check "unquoted path with spaces is rejoined" "$(q "$out" '.slug == "my-prd" and .budget == 2')"
out=$(bash "$init" top 5 "My PRD.md")
check "top N overrides the budget" "$(q "$out" '.budget == 5 and (.budget_default | not)')"
out=$(bash "$init" "My PRD.md" top 0)
check "top 0 is an error" "$(q "$out" '.error == "bad_budget"')"
out=$(bash "$init" 123)
check "bare number is a PR, deferred" "$(q "$out" '.error == "pr_deferred"')"
out=$(bash "$init" https://github.com/o/r/pull/9)
check "PR URL is deferred" "$(q "$out" '.error == "pr_deferred"')"
out=$(bash "$init")
check "no path is an error" "$(q "$out" '.error == "no_artifact"')"
out=$(bash "$init" missing.md)
check "missing file is an error" "$(q "$out" '.error == "not_found"')"
out=$(bash "$init" blank.md)
check "blank file is an error" "$(q "$out" '.error == "empty_artifact"')"
out=$(bash "$init" done-essence.md)
check "an essence output is refused" "$(q "$out" '.error == "already_distilled"')"
p1=$(bash "$init" "My PRD.md" | jq -r .out_path); touch "$p1"; p2=$(bash "$init" "My PRD.md" | jq -r .out_path)
check "out path never collides" "$([ "$p1" != "$p2" ] && [ "${p2%-essence-2.md}" != "$p2" ]; echo $?)"

good='{"budget":2,"intent":"x","candidates":[
  {"id":"C1","claim":"a","locator":"## Goals","bucket":"vital","absorbs":["C4"]},
  {"id":"C2","claim":"b","locator":"## Security","bucket":"non_negotiable"},
  {"id":"C3","claim":"c","locator":"## Ideas","bucket":"parked","reason":"off-intent"},
  {"id":"C4","claim":"d","locator":"## Goals","bucket":"merged","into":"C1"},
  {"id":"C5","claim":"e","locator":"## Scope","bucket":"vital"}]}'
ledger() { printf '%s' "$1" > "$tmp/l.json"; bash "$check_ledger" "$tmp/l.json"; }

out=$(ledger "$good"); rc=$?
check "valid ledger passes with counts" "$([ $rc = 0 ] && [ "$(q "$out" '.ok and .counts == {vital:2,non_negotiable:1,parked:1,merged:1,total:5}')" = 0 ]; echo $?)"
out=$(ledger "$(jq -c '.candidates[2].reason = ""' <<< "$good")"); rc=$?
check "parked without reason fails" "$([ $rc = 1 ] && [ "$(q "$out" '.errors | any(test("C3: parked without a reason"))')" = 0 ]; echo $?)"
out=$(ledger "$(jq -c '.budget = 1' <<< "$good")")
check "vital over budget fails" "$(q "$out" '.errors | any(test("exceed the budget"))')"
out=$(ledger "$(jq -c '.budget = 1 | .candidates[4].bucket = "non_negotiable"' <<< "$good")")
check "non-negotiables do not count against the budget" "$(q "$out" '.ok')"
out=$(ledger "$(jq -c '.candidates[3].into = "C3"' <<< "$good")")
check "merge into a non-vital fails" "$(q "$out" '.errors | any(test("C4: merged into C3, which is not vital"))')"
out=$(ledger "$(jq -c '.candidates[0].absorbs = []' <<< "$good")")
check "merge missing from target absorbs fails" "$(q "$out" '.errors | any(test("does not list it in absorbs"))')"
out=$(ledger "$(jq -c '.candidates[4].absorbs = ["C3"]' <<< "$good")")
check "absorbing a non-merged item fails" "$(q "$out" '.errors | any(test("C5: absorbs C3"))')"
out=$(ledger "$(jq -c '.candidates[1].locator = ""' <<< "$good")")
check "candidate without locator fails" "$(q "$out" '.errors | any(test("C2: no source locator"))')"
out=$(ledger "$(jq -c '.candidates[1].id = "C1"' <<< "$good")")
check "duplicate id fails" "$(q "$out" '.errors | any(test("duplicate id C1"))')"
out=$(ledger "$(jq -c '.candidates[2].bucket = "maybe"' <<< "$good")")
check "unknown bucket fails" "$(q "$out" '.errors | any(test("C3: bucket must be"))')"
out=$(ledger '{"budget":3,"candidates":[{"id":"C1","claim":"a","locator":"x","bucket":"parked","reason":"r"}]}')
check "nothing kept fails" "$(q "$out" '.errors | any(test("no vital direction or non-negotiable kept"))')"
out=$(ledger '{"budget":3,"candidates":[{"id":"C1","claim":"a","locator":"x","bucket":"non_negotiable"}]}')
check "all non-negotiable passes" "$(q "$out" '.ok')"
printf 'not json' > "$tmp/bad.json"; out=$(bash "$check_ledger" "$tmp/bad.json")
check "unreadable ledger is an error" "$(q "$out" '.error == "bad_json"')"

exit $fail
