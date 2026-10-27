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

run() { printf '%s' "$1" | bash "$init"; }
printf '# spec\n- one\n' > "spec (1).md"
printf '# q3\n- one\n' > "Q3 top 10 risks.md"
printf '# dbl\n- one\n' > "a  b.md"
mkdir -p pull/5 && printf '# in pull dir\n- one\n' > pull/5/spec.md

out=$(bash "$init" "My PRD.md")
check "default budget is 3, slug is kebab-case" "$(q "$out" '.budget == 3 and (.out_path | endswith(".bf/essence/my-prd-essence.md")) and (keys == ["budget","ledger_path","out_path","source"])')"
out=$(bash "$init" My PRD.md)
check "unquoted positional path with spaces is rejoined" "$(q "$out" '.source | endswith("/My PRD.md")')"
out=$(bash "$init" top 5 "My PRD.md")
check "top N overrides the budget" "$(q "$out" '.budget == 5')"
out=$(run 'top 2 My PRD.md')
check "stdin: leading top N, path with spaces" "$(q "$out" '.budget == 2 and (.source | endswith("/My PRD.md"))')"
out=$(run '  top   2   My PRD.md  ')
check "stdin: surrounding whitespace is trimmed" "$(q "$out" '.budget == 2 and (.source | endswith("/My PRD.md"))')"
out=$(run 'a  b.md')
check "interior double spaces are preserved" "$(q "$out" '.source | endswith("/a  b.md")')"
out=$(run 'spec (1).md')
check "path with parentheses survives" "$(q "$out" '.source | endswith("/spec (1).md")')"
out=$(run 'Q3 top 10 risks.md')
check "top inside the path is part of the path" "$(q "$out" '.budget == 3 and (.source | endswith("/Q3 top 10 risks.md"))')"
out=$(run 'top 0 My PRD.md')
check "top 0 is an error" "$(q "$out" '.error == "bad_budget"')"
out=$(run 'top abc My PRD.md')
check "top with a non-integer is an error" "$(q "$out" '.error == "bad_budget"')"
out=$(run 'top')
check "bare top is an error" "$(q "$out" '.error == "bad_budget"')"
out=$(run 'top 2')
check "top N without a path is no_artifact" "$(q "$out" '.error == "no_artifact"')"
out=$(run '#123')
check "#N is a PR, deferred" "$(q "$out" '.error == "pr_deferred" and (.detail | test("walkthrough") | not)')"
out=$(run '123')
check "bare number is a PR, deferred" "$(q "$out" '.error == "pr_deferred"')"
out=$(run 'https://github.com/o/r/pull/9')
check "PR URL is deferred" "$(q "$out" '.error == "pr_deferred"')"
out=$(run 'pull/5/spec.md')
check "existing file under a pull/ dir is accepted" "$(q "$out" '.source | endswith("/pull/5/spec.md")')"
out=$(run '')
check "no path is an error" "$(q "$out" '.error == "no_artifact"')"
out=$(run 'missing.md')
check "missing file is an error" "$(q "$out" '.error == "not_found"')"
out=$(run 'say "hi".md')
check "error JSON stays valid with a quote in the path" "$(q "$out" '.error == "not_found" and .detail == "say \"hi\".md"')"
out=$(run 'blank.md')
check "blank file is an error" "$(q "$out" '.error == "empty_artifact"')"
out=$(run 'done-essence.md')
check "an essence output is refused" "$(q "$out" '.error == "already_distilled"')"
p1=$(bash "$init" "My PRD.md" | jq -r .out_path); touch "$p1"; p2=$(bash "$init" "My PRD.md" | jq -r .out_path)
check "out path never collides with an output" "$([ "$p1" != "$p2" ] && [ "${p2%-essence-2.md}" != "$p2" ]; echo $?)"
rm -f "$p1"; touch "${p1%.md}.ledger.json"; p3=$(bash "$init" "My PRD.md" | jq -r .out_path)
check "out path never collides with a ledger" "$([ "${p3%-essence-2.md}" != "$p3" ]; echo $?)"

good='{"budget":2,"intent":"x","candidates":[
  {"id":"C1","claim":"a","locator":"## Goals","bucket":"vital"},
  {"id":"C2","claim":"b","locator":"## Security","bucket":"non_negotiable"},
  {"id":"C3","claim":"c","locator":"## Ideas","bucket":"parked","reason":"off-intent"},
  {"id":"C4","claim":"d","locator":"## Goals","bucket":"merged","into":"C1"},
  {"id":"C5","claim":"e","locator":"## Scope","bucket":"vital"}]}'
ledger() { printf '%s' "$1" > "$tmp/l.json"; bash "$check_ledger" "$tmp/l.json"; }
errs() { q "$out" ".errors | any(test(\"$1\"))"; }

out=$(ledger "$good"); rc=$?
check "valid ledger passes with counts" "$([ $rc = 0 ] && [ "$(q "$out" '.ok and .counts == {vital:2,non_negotiable:1,parked:1,merged:1,total:5}')" = 0 ]; echo $?)"
out=$(ledger "$(jq -c '.candidates[2].reason = ""' <<< "$good")"); rc=$?
check "parked without reason fails" "$([ $rc = 1 ] && [ "$(errs 'C3: parked without a reason')" = 0 ]; echo $?)"
out=$(ledger "$(jq -c '.candidates[2].reason = 5' <<< "$good")")
check "non-string reason fails" "$(errs 'C3: parked without a reason')"
out=$(ledger "$(jq -c '.budget = 1' <<< "$good")")
check "vital over budget fails" "$(errs 'exceed the budget')"
out=$(ledger "$(jq -c '.budget = 1 | .candidates[4].bucket = "non_negotiable"' <<< "$good")")
check "non-negotiables do not count against the budget" "$(q "$out" '.ok')"
out=$(ledger "$(jq -c '.candidates[3].into = "C3"' <<< "$good")")
check "merge into a non-vital fails" "$(errs 'C4: merged into C3, which is not vital')"
out=$(ledger "$(jq -c 'del(.candidates[3].into)' <<< "$good")")
check "merge without into fails" "$(errs 'C4: merged without an into')"
out=$(ledger "$(jq -c '.candidates[3].into = ["C1"]' <<< "$good")")
check "non-string into fails without crashing" "$(errs 'C4: merged without an into')"
out=$(ledger "$(jq -c '.candidates[0].absorbs = ["C3"]' <<< "$good")")
check "absorbs is not part of the shape" "$(q "$out" '.ok')"
out=$(ledger "$(jq -c '.candidates[1].locator = ""' <<< "$good")")
check "candidate without locator fails" "$(errs 'C2: no source locator')"
out=$(ledger "$(jq -c '.candidates[1].claim = 7' <<< "$good")")
check "non-string claim fails" "$(errs 'C2: claim must be')"
out=$(ledger "$(jq -c '.candidates[1].id = "C1"' <<< "$good")")
check "duplicate id fails" "$(errs 'duplicate id C1')"
out=$(ledger "$(jq -c 'del(.candidates[1].id) | del(.candidates[2].id)' <<< "$good")")
check "missing ids are reported once each, not as duplicates" "$([ "$(q "$out" '.errors | map(select(test("duplicate"))) | length == 0')" = 0 ] && [ "$(q "$out" '.errors | map(select(test("id must be"))) | length == 2')" = 0 ]; echo $?)"
out=$(ledger "$(jq -c '.candidates[2].bucket = "maybe"' <<< "$good")")
check "unknown bucket fails" "$(errs 'C3: bucket must be')"
out=$(ledger "$(jq -c '.candidates[2].bucket = ["parked"]' <<< "$good")")
check "non-string bucket fails without crashing" "$(errs 'C3: bucket must be')"
out=$(ledger "$(jq -c '.candidates += ["C9", 4]' <<< "$good")")
check "non-object candidates are errors" "$(errs 'is not an object')"
out=$(ledger "$(jq -c '.candidates = {}' <<< "$good")")
check "candidates must be an array" "$(errs 'candidates must be a non-empty array')"
out=$(ledger "$(jq -c '.candidates = []' <<< "$good")")
check "empty candidates fails" "$(errs 'candidates must be a non-empty array')"
out=$(ledger "$(jq -c '.budget = 1.5' <<< "$good")")
check "fractional budget fails" "$(errs 'budget must be an integer')"
out=$(ledger "$(jq -c '.budget = "3"' <<< "$good")")
check "string budget fails" "$(errs 'budget must be an integer')"
out=$(ledger "$(jq -c 'del(.budget)' <<< "$good")")
check "missing budget fails" "$(errs 'budget must be an integer')"
out=$(ledger "$(jq -c 'del(.intent)' <<< "$good")")
check "missing intent fails" "$(errs 'intent must be')"
out=$(ledger "$(jq -c '.intent = 3' <<< "$good")")
check "non-string intent fails" "$(errs 'intent must be')"
out=$(ledger '{"budget":3,"intent":"x","candidates":[{"id":"C1","claim":"a","locator":"x","bucket":"parked","reason":"r"}]}')
check "nothing kept fails" "$(errs 'no vital direction kept')"
out=$(ledger '{"budget":3,"intent":"x","candidates":[{"id":"C1","claim":"a","locator":"x","bucket":"non_negotiable"}]}')
check "all non-negotiable passes" "$(q "$out" '.ok')"
out=$(ledger '{"budget":3,"intent":"x","candidates":[{"id":"C1","claim":"a","locator":"x","bucket":"non_negotiable"},{"id":"C2","claim":"b","locator":"y","bucket":"parked","reason":"r"}]}')
check "a non-negotiable does not excuse cutting every direction" "$(errs 'no vital direction kept')"
printf 'not json' > "$tmp/bad.json"; out=$(bash "$check_ledger" "$tmp/bad.json")
check "unreadable ledger is an error" "$(q "$out" '.error == "bad_json"')"

exit $fail
