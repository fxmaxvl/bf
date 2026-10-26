#!/usr/bin/env bash
# Smoke check for hunt-init.sh scope resolution and findings.sh merge/resolve, against throwaway repos.
#
# Usage: bug-hunt-smoke.sh
# Contract: exits 0 when every case passes, 1 otherwise; prints one PASS/FAIL line per case.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
init="$here/hunt-init.sh"
findings="$here/findings.sh"
command -v jq >/dev/null || { echo "FAIL jq is required"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # name, condition-exit-status
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}
q() { jq -e "$2" <<< "$1" >/dev/null; echo $?; }

mkdir -p "$tmp/origin" && cd "$tmp/origin" && git init -q -b main . && git config user.email t@t && git config user.name t
mkdir -p src/api lib && echo a > src/api/a.js && echo b > lib/b.js && git add . && git commit -qm init
git clone -q "$tmp/origin" "$tmp/r" && cd "$tmp/r" && git config user.email t@t && git config user.name t
git switch -qc feat && echo change >> src/api/a.js && git commit -qam change

out=$(bash "$init")
check "branch: default scope is the branch diff" "$(q "$out" '.mode == "branch" and .files == ["src/api/a.js"] and .base != null and .diff_file != null')"
out=$(bash "$init" lib)
check "paths: tracked files under the path, no base" "$(q "$out" '.mode == "paths" and .files == ["lib/b.js"] and .base == null')"
out=$(bash "$init" --repo --repro)
check "repo: every tracked file, repro flag" "$(q "$out" '.mode == "repo" and .file_count == 2 and .repro == true')"
out=$(bash "$init" --hunters 9 --lenses security,logic,security)
check "overrides: hunters capped at 6, lenses deduped" "$(q "$out" '.hunters == 6 and .hunters_capped and .lenses == ["security","logic"]')"
out=$(bash "$init" --lenses bogus)
check "bad lens is an error" "$(q "$out" '.error == "unknown_lens"')"
out=$(bash "$init" --repo lib)
check "repo plus path is an error" "$(q "$out" '.error == "conflicting_scope"')"
r1=$(bash "$init" | jq -r .report_path); touch "$r1"; r2=$(bash "$init" | jq -r .report_path)
check "report path never collides" "$([ "$r1" != "$r2" ]; echo $?)"

run="$tmp/run"; mkdir -p "$run/hunters" "$run/verifiers"
cat > "$run/hunters/h1.json" <<'J'
{"hunter_id":"h1","lens":"logic","findings":[
 {"file":"src/a.js","line":10,"severity":"medium","title":"off by one"},
 {"file":"src/a.js","line":14,"severity":"high","title":"other bug"},
 {"file":"src/a.js","line":16,"severity":"low","title":"third"}]}
J
cat > "$run/hunters/h2.json" <<'J'
{"hunter_id":"h2","lens":"errors","findings":[
 {"file":"src/a.js","line":12,"severity":"critical","title":"same bug, other lens"},
 {"file":"lib/b.js","line":3,"severity":"medium","title":"swallowed error"}]}
J
cat > "$run/hunters/h3.json" <<'J'
{"hunter_id":"h3","lens":"security","findings":[{"file":"src/a.js","line":11,"severity":"low","title":"dup again"}]}
J
cat > "$run/hunters/h4.json" <<'J'
{"hunter_id":"h4","lens":"data","findings":[{"file":"src/a.js","line":10,"title":"dup"}, {"file":"src/a.js","line":10,"title":"dup2"}]}
J
cat > "$run/hunters/h4b.json" <<'J'
{"hunter_id":"h4","lens":"contracts","findings":[{"file":"src/a.js","line":14,"title":"same hunter, second lens"}]}
J
echo 'not json' > "$run/hunters/h5.json"
m=$(bash "$findings" merge "$run")
check "merge: ±2 is anchored, not chained (10,11,12 | 14,16)" "$(q "$m" '[.findings[] | select(.file == "src/a.js") | .line] | sort == [10,14]')"
check "merge: sources count distinct hunters" "$(q "$m" '(.findings[] | select(.line == 10) | .sources) == 4')"
check "merge: one hunter on two lenses is one source" "$(q "$m" '(.findings[] | select(.line == 14) | .sources == 2 and (.lenses | length) == 2)')"
check "merge: highest severity wins, ids ordered by severity" "$(q "$m" '.findings[0].severity == "critical" and .findings[0].id == "F1"')"
check "merge: nothing dropped" "$(q "$m" '([.findings[].members[]] | length) == 9')"
check "merge: invalid hunter output reported" "$(q "$m" '.invalid == ["h5"]')"

mkdir -p "$tmp/pack/hunters"
for d in a b c d e f g h; do
  printf '{"hunter_id":"h-%s","lens":"logic","findings":[{"file":"%s/x.js","line":1,"severity":"medium","title":"t"}]}\n' "$d" "$d" > "$tmp/pack/hunters/$d.json"
done
p=$(bash "$findings" merge "$tmp/pack")
check "pack: 8 directories fit in 6 batches, none dropped" "$(q "$p" '(.batches | length) == 6 and ([.batches[].finding_ids[]] | length) == 8')"
check "pack: neighbouring directories merge first" "$(q "$p" '.batches[0].dirs == ["a","b"]')"
p=$(bash "$findings" merge "$tmp/pack" 2)
check "pack: cap is honoured" "$(q "$p" '(.batches | length) == 2')"

b1=$(jq -r '.batches[] | select(.dirs | index("src")) | .id' <<< "$m")
f1=$(jq -r '.findings[] | select(.line == 10) | .id' <<< "$m")
printf '{"batch_id":"%s","verdicts":[{"id":"%s","verdict":"confirmed","note":"real"}]}\n' "$b1" "$f1" > "$run/verifiers/$b1.json"
fin=$(bash "$findings" resolve "$run")
check "resolve: verdict joined" "$(q "$fin" '.findings[] | select(.id == "'"$f1"'") | .verdict == "confirmed"')"
check "resolve: missing verdicts are unverified, failed batch listed" "$(q "$fin" '(.counts.unverified >= 1) and (.failed_batches | length) >= 1')"

exit $fail
