#!/usr/bin/env bash
# Smoke check for hunt-init.sh scope resolution, profile.sh signal counts and suggestions, and findings.sh merge/resolve/analyze/mark/timing, against throwaway repos.
#
# Usage: bug-hunt-smoke.sh
# Contract: exits 0 when every case passes, 1 otherwise; prints one PASS/FAIL line per case.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
init="$here/hunt-init.sh"
findings="$here/findings.sh"
skill="$here/../SKILL.md"
command -v jq >/dev/null || { echo "FAIL jq is required"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # name, condition-exit-status
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}
q() { jq -e "$2" <<< "$1" >/dev/null; echo $?; }
same() { [ "$1" = "$2" ]; echo $?; }

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
out=$(bash "$init" --lenses flow)
check "flow lens is accepted" "$(q "$out" '.lenses == ["flow"]')"
out=$(bash "$init" --lenses bogus)
check "bad lens is an error" "$(q "$out" '.error == "unknown_lens"')"
out=$(bash "$init" --repo lib)
check "repo plus path is an error" "$(q "$out" '.error == "conflicting_scope"')"
out=$(bash "$init" 'no"such')
check "an error detail with a quote is valid JSON" "$(q "$out" '.error == "no_such_path" and .detail == "no\"such"')"
out=$(bash "$init" --worktree)
check "--worktree without --pr is an error" "$(q "$out" '.error == "worktree_needs_pr"')"
# alarm 5: a regression to the old parse loop fails here instead of hanging the smoke.
out=$(perl -e 'alarm 5; exec @ARGV' bash "$init" --pr)
check "--pr with no value is missing_value, not a hang" "$(q "$out" '.error == "missing_value"')"
out=$(perl -e 'alarm 5; exec @ARGV' bash "$init" --bogus)
check "unknown flag is unknown_flag, not a hang" "$(q "$out" '.error == "unknown_flag"')"
r1=$(bash "$init" | jq -r .report_path); touch "$r1"; r2=$(bash "$init" | jq -r .report_path)
check "report path never collides" "$([ "$r1" != "$r2" ]; echo $?)"

out=$(bash "$init" lib)
check "profile: paths scope has no diff, one code file, no signals" "$(q "$out" '.profile.lines_changed == null and .profile.scanned == 1 and .profile.modules == 1 and .profile.file_kinds.code == 1 and .profile.lenses.logic == 1 and ([.profile.lenses | del(.logic)[]] | add) == 0 and ([.profile.unowned[]] | add) == 0 and .profile.suggestions == []')"
out=$(bash "$init")
check "profile: branch scope counts added and removed lines" "$(q "$out" '.profile.lines_changed == {"added":1,"removed":0}')"
bogus=$(bash "$init" --lenses bogus | jq -r '.detail | sub(".*valid: "; "") | rtrimstr(")") | split(" ") | sort | @json')
check "profile: lens keys match the LENSES list" "$(q "$out" ".profile.lenses | keys == $bogus")"
table_ids() { # table name: the backticked ids in the first column of the SKILL.md table headed "| id | <name> |"
  awk -v h="| id | $1 |" 'index($0, h) == 1 { on = 1; next } on && /^\|/ { if ($0 !~ /^\|[-| ]+\|$/) { split($0, c, "`"); print c[2] } next } { on = 0 }' "$skill" | sort | tr '\n' ' '
}
check "profile: lens keys match the SKILL.md lens table" "$(same "$(table_ids Lens)" "$(jq -r '.profile.lenses | keys | join(" ") + " "' <<< "$out")")"
check "profile: class keys match the SKILL.md class table" "$(same "$(table_ids Class)" "$(jq -r '.profile.unowned | keys | join(" ") + " "' <<< "$out")")"
check "SKILL.md report template: Lens suggestions sits between Coverage and Handoff" "$(same "$(awk '/^## Coverage$/ { c = NR } /^## Lens suggestions$/ { l = NR } /^## Handoff$/ { h = NR } END { print (c && l > c && h > l) ? "ok" : "bad" }' "$skill")" ok)"
check "profile: every file kind key is present" "$(q "$out" '.profile.file_kinds | keys == ["code","config","docs","other","skill","style","test"]')"
check "help text names the profile key" "$(same "$(bash "$init" --help | grep -q profile && echo y)" y)"
out=$(echo lib/b.js | HUNT_LENSES="logic bogus" bash "$here/profile.sh")
check "profile: a lens id with no signal row is an error" "$(q "$out" '.error == "no_signal"')"
out=$(echo lib/b.js | env -u HUNT_LENSES bash "$here/profile.sh")
check "profile: missing HUNT_LENSES is an error" "$(q "$out" '.error == "no_lenses"')"

# A second repo keeps the $tmp/r assertions (file_count, files) valid.
mkdir -p "$tmp/sig-origin/src" "$tmp/sig-origin/web" "$tmp/sig-origin/skills/x" "$tmp/sig-origin/docs"
cd "$tmp/sig-origin" && git init -q -b main . && git config user.email t@t && git config user.name t
printf '%s\n' 'async function run() {' 'await fetch(u)' 'try {' '} catch (e) {' 'const t = new Date()' 'x.toFixed(2)' > src/job.js
printf '%s\n' '// author: bob' 'const x = 1' > src/plain.js
echo 'a { color: red }' > web/a.css
printf '%s\n' '## Phase 1 - Pick' '## Phase 2 - Run' > skills/x/SKILL.md
echo 'const p = createPool()' > old.js
echo 'cache secret retry' > docs/notes.md
git add . && git commit -qm init
git clone -q "$tmp/sig-origin" "$tmp/sig" && cd "$tmp/sig" && git config user.email t@t && git config user.name t
git switch -qc feat && printf '%s\n' 'const y = 2' 'const z = 3' >> src/job.js && git rm -q old.js && git commit -qam change

out=$(bash "$init" src)
check "profile signals: fire where the content matches and stay 0 elsewhere" "$(q "$out" '.profile.lines_changed == null and .profile.lenses.concurrency == 1 and .profile.lenses.errors == 1 and .profile.lenses.security == 0 and .profile.unowned.time == 1 and .profile.unowned["numeric-precision"] == 1 and .profile.unowned["resource-leak"] == 0 and .profile.unowned["cache-invalidation"] == 0')"
check "profile suggestions: classes at 10% of scanned files, in table order" "$(q "$out" '.profile.scanned == 2 and .profile.suggestions == ["time","numeric-precision"]')"
out=$(bash "$init" --repo)
check "profile repo: kinds, modules, and docs files add no signal" "$(q "$out" '.profile.file_kinds.style == 1 and .profile.file_kinds.skill == 1 and .profile.file_kinds.docs == 1 and .profile.file_kinds.code == 2 and .profile.lenses.flow >= 1 and .profile.lenses.logic == 3 and .profile.unowned["cache-invalidation"] == 0 and .profile.lenses.security == 0 and .profile.modules == 4 and .profile.lenses.contracts >= 1 and .profile.scanned == 2')"
out=$(bash "$init")
check "profile branch: a deleted file is listed but not counted" "$(q "$out" '(.files | index("old.js")) != null and .profile.unowned["resource-leak"] == 0 and .profile.lines_changed.added == 2 and .profile.lines_changed.removed == 1')"
out=$(bash "$init" --lenses security)
check "profile survives a lens override" "$(q "$out" '.lenses == ["security"] and .profile.scanned >= 1')"

# Blank lines and content that starts with ++ or -- are diff lines, not headers.
mkdir -p "$tmp/ln-origin" && cd "$tmp/ln-origin" && git init -q -b main . && git config user.email t@t && git config user.name t
printf '%s\n' 'a' '-- old comment' 'b' > q.sql && git add . && git commit -qm init
git clone -q "$tmp/ln-origin" "$tmp/ln" && cd "$tmp/ln" && git config user.email t@t && git config user.name t
git switch -qc feat && printf '%s\n' 'a' 'b' '' '++i' '-- new comment' > q.sql && git commit -qam change
out=$(bash "$init")
check "profile lines_changed: blank, ++ and -- content lines count inside hunks" "$(q "$out" '.profile.lines_changed == {"added":3,"removed":1}')"

# A signal that only a test file carries is not real use: the class stays 0 and nothing is suggested.
mkdir -p "$tmp/tt" && cd "$tmp/tt" && git init -q -b main . && git config user.email t@t && git config user.name t
printf '%s\n' 'const t = new Date()' > a.test.js && echo 'const x = 1' > b.js && git add . && git commit -qm init
out=$(bash "$init" --repo)
check "profile: a signal in a test file only leaves the class at 0" "$(q "$out" '.profile.unowned.time == 0 and .profile.suggestions == [] and .profile.scanned == 1')"
out=$(echo gone.js | HUNT_LENSES="logic errors" bash "$here/profile.sh" 2>&1)
check "profile: a scope of deleted files gives zero counts and no stderr" "$(q "$out" '.scanned == 0 and .modules == 0 and .lenses == {"logic":0,"errors":0} and .suggestions == []')"
# A copy of the plugin scripts without profile.sh makes the helper fail.
mkdir -p "$tmp/plug/skills" && cp -R "$here/.." "$tmp/plug/skills/bug-hunt" && cp -R "$here/../../coherence" "$tmp/plug/skills/coherence"
rm "$tmp/plug/skills/bug-hunt/scripts/profile.sh"
out=$(bash "$tmp/plug/skills/bug-hunt/scripts/hunt-init.sh" --repo)
check "profile: a failing helper gives a null profile and the hunt goes on" "$(q "$out" '.profile == null and .mode == "repo" and .file_count == 2')"

# --worktree: a stub gh answers `gh pr view`, a local bare origin carries main and refs/pull/<n>/head, and
# HOME points into $tmp so every worktree lands there.
wbare="$tmp/wt-bare.git"; whome="$tmp/wt-home"; mkdir -p "$tmp/bin" "$whome"
cat > "$tmp/bin/gh" <<'G'
#!/usr/bin/env bash
[ "$1 $2 $4 $5" = "pr view --json headRefOid,headRefName,baseRefName" ] || exit 1
printf '{"headRefOid":"%s","headRefName":"pr-branch","baseRefName":"main"}\n' "$STUB_OID"
G
chmod +x "$tmp/bin/gh"
git init -q --bare -b main "$wbare"
git init -q -b main "$tmp/wt-seed" && cd "$tmp/wt-seed" && git config user.email t@t && git config user.name t
git remote add origin "$wbare" && echo base > f && git add f && git commit -qm base && git push -q origin main
make_pr() { # PR number, file content: push a commit on top of main to refs/pull/<n>/head (forced) and print its sha
  ( cd "$tmp/wt-seed" && git switch -q --detach main && echo "$2" > "pr$1.txt" && git add "pr$1.txt" &&
    git commit -qm "pr $1 $2" && git push -q -f origin "HEAD:refs/pull/$1/head" && git rev-parse HEAD )
}
hi() { # repo dir, stub head sha, hunt-init args
  ( cd "$1" && env HOME="$whome" PATH="$tmp/bin:$PATH" STUB_OID="$2" bash "$init" "${@:3}" )
}
git clone -q "$wbare" "$tmp/wt" && git -C "$tmp/wt" config user.email t@t && git -C "$tmp/wt" config user.name t
wt1="$whome/.bf/bug-hunt/worktrees/wt-pr-1"
oid1=$(make_pr 1 one)
out=$(hi "$tmp/wt" "$oid1" --pr 1 --worktree)
check "worktree: create sets the worktree key and keeps run_dir and report_path under root" "$(q "$out" ". as \$o | \$o.mode == \"pr\" and \$o.worktree == \"$wt1\" and \$o.worktree != \$o.root and (\$o.run_dir | startswith(\$o.root + \"/\")) and (\$o.report_path | startswith(\$o.root + \"/\")) and \$o.files == [\"pr1.txt\"]")"
check "worktree: create puts HEAD at the PR head and leaves the user's checkout alone" "$(same "$(git -C "$wt1" rev-parse HEAD)|$(git -C "$tmp/wt" rev-parse --abbrev-ref HEAD)" "$oid1|main")"
oid2=$(make_pr 1 two)
out=$(hi "$tmp/wt" "$oid2" --pr 1 --worktree)
check "worktree: reuse moves the existing worktree to the new PR head" "$(q "$out" ".worktree == \"$wt1\" and .pr == 1")"
check "worktree: reuse leaves HEAD at the new head" "$(same "$(git -C "$wt1" rev-parse HEAD)" "$oid2")"
out=$(hi "$tmp/wt" "$oid1" --pr 1)
check "worktree: pr_not_checked_out names the path --worktree would use" "$(q "$out" ".error == \"pr_not_checked_out\" and .worktree_path == \"$wt1\"")"
git -C "$tmp/wt" switch -q -c pr-branch
out=$(hi "$tmp/wt" "$oid1" --pr 1)
check "worktree: pr_not_checked_out on the PR branch names the path too" "$(q "$out" ".error == \"pr_not_checked_out\" and .worktree_path == \"$wt1\"")"
git -C "$tmp/wt" switch -q main
echo stray > "$wt1/stray"
out=$(hi "$tmp/wt" "$oid2" --pr 1 --worktree)
check "worktree: local changes are worktree_dirty" "$(q "$out" '.error == "worktree_dirty"')"
rm "$wt1/stray"
out=$(hi "$tmp/wt" "$oid1" --pr 1 --worktree)
check "worktree: a stub head that differs from refs/pull/<n>/head is pr_head_moved" "$(q "$out" '.error == "pr_head_moved"')"
oid3=$(make_pr 2 three)
mkdir -p "$whome/.bf/bug-hunt/worktrees/wt-pr-2"
out=$(hi "$tmp/wt" "$oid3" --pr 2 --worktree)
check "worktree: a directory that is not a worktree of this repo is worktree_failed" "$(q "$out" '.error == "worktree_failed"')"
git -C "$tmp/wt" worktree remove --force "$wt1"
oid4=$(make_pr 3 four)
wt3="$whome/.bf/bug-hunt/worktrees/wt-pr-3"
hi "$tmp/wt" "$oid4" --pr 3 --worktree >/dev/null
rm -rf "$wt3"
out=$(hi "$tmp/wt" "$oid4" --pr 3 --worktree)
check "worktree: a folder deleted with rm -rf is created again" "$(q "$out" ".worktree == \"$wt3\"")"
check "worktree: the recreated worktree is at the PR head" "$(same "$(git -C "$wt3" rev-parse HEAD)" "$oid4")"
git -C "$tmp/wt" worktree remove --force "$wt3"
out=$(hi "$tmp/wt" "$oid4" --pr https://github.com/acme/other/pull/3 --worktree)
check "worktree: a PR URL of another repository is worktree_other_repo" "$(q "$out" '.error == "worktree_other_repo" and (.detail | contains("acme/other"))')"
# A GitHub-style origin URL that insteadOf maps to the local bare repo: the same repository's PR URL goes through.
git clone -q "$wbare" "$tmp/wtu" && git -C "$tmp/wtu" config user.email t@t && git -C "$tmp/wtu" config user.name t
git -C "$tmp/wtu" remote set-url origin https://github.com/Acme/wtu.git
git -C "$tmp/wtu" config url."$wbare".insteadOf https://github.com/Acme/wtu.git
wtu="$whome/.bf/bug-hunt/worktrees/wtu-pr-3"
out=$(hi "$tmp/wtu" "$oid4" --pr https://github.com/acme/WTU/pull/3/files --worktree)
check "worktree: a PR URL of the origin repository passes, whatever its case" "$(q "$out" ".worktree == \"$wtu\"")"
git -C "$tmp/wtu" worktree remove --force "$wtu"
cd "$tmp/r" || exit 1

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
check "merge: a file not named after its hunter_id adds nothing and is listed" "$(q "$m" '(.findings[] | select(.line == 14) | .sources == 1 and .lenses == ["logic"]) and .ignored == ["hunters/h4b.json"]')"
check "merge: highest severity wins, ids ordered by severity" "$(q "$m" '.findings[0].severity == "critical" and .findings[0].id == "F1"')"
check "merge: nothing dropped" "$(q "$m" '([.findings[].members[]] | length) == 8')"
check "merge: invalid hunter output reported" "$(q "$m" '.invalid == ["h5"]')"

mkdir -p "$tmp/pack/hunters"
for d in a b c d e f g h; do
  printf '{"hunter_id":"h-%s","lens":"logic","findings":[{"file":"%s/x.js","line":1,"severity":"medium","title":"t"}]}\n' "$d" "$d" > "$tmp/pack/hunters/h-$d.json"
done
p=$(bash "$findings" merge "$tmp/pack")
check "pack: 8 directories fit in 6 batches, none dropped" "$(q "$p" '(.batches | length) == 6 and ([.batches[].finding_ids[]] | length) == 8')"
check "pack: neighbouring directories merge first" "$(q "$p" '.batches[0].dirs == ["a","b"]')"
p=$(bash "$findings" merge "$tmp/pack" 2)
check "pack: cap is honoured" "$(q "$p" '(.batches | length) == 2')"

b1=$(jq -r '.batches[] | select(.dirs | index("src")) | .id' <<< "$m")
f1=$(jq -r '.findings[] | select(.line == 10) | .id' <<< "$m")
printf '{"batch_id":"%s","verdicts":[{"id":"%s","verdict":"confirmed","note":"real"}]}\n' "$b1" "$f1" > "$run/verifiers/$b1.json"
# A stray verifier file: its verdicts must not count, so counts.surviving stays 1 below.
jq -c '{batch_id: "B1", verdicts: [.findings[] | {id, verdict: "confirmed", note: "stray"}]}' <<< "$m" > "$run/verifiers/B1.input.json"
fin=$(bash "$findings" resolve "$run")
check "resolve: verdict joined" "$(q "$fin" '.findings[] | select(.id == "'"$f1"'") | .verdict == "confirmed"')"
check "resolve: surviving flag and count follow the verdict" "$(q "$fin" '(.findings[] | select(.id == "'"$f1"'") | .surviving) == true and (.findings | map(select(.verdict == "unverified" and .surviving)) | length) == 0 and .counts.surviving == 1')"
check "resolve: missing verdicts are unverified, failed batch listed" "$(q "$fin" '(.counts.unverified >= 1) and (.failed_batches | length) >= 1')"
check "merge: the top-severity member carries the cluster id, the rest get member ids" "$(q "$m" '.findings[] | select(.line == 10) | .members[0].id == .id and .members[0].severity == .severity and ([.members[1:][].id] == [range(2; .members | length + 1) as $i | "\(.id).\($i)"])')"
check "resolve: no member verdict, no split" "$(q "$fin" '(.findings | length) == '"$(jq '.findings | length' <<< "$m")"' and all(.findings[]; has("split_from") | not)')"

sp="$tmp/split"; mkdir -p "$sp/verifiers" && cp -R "$run/hunters" "$sp/"
sm=$(bash "$findings" merge "$sp")
sb=$(jq -r '.batches[] | select(.dirs | index("src")) | .id' <<< "$sm")
sid=$(jq -r '.findings[] | select(.line == 10) | .members[1].id' <<< "$sm")
sh=$(jq -r '.findings[] | select(.line == 10) | .members[1].hunter_id' <<< "$sm")
sn=$(jq '.findings | length' <<< "$sm"); sk=$(jq '.findings[] | select(.line == 10) | .members | length - 1' <<< "$sm")
printf '{"batch_id":"%s","verdicts":[{"id":"%s","verdict":"confirmed","note":"real"},{"id":"%s","verdict":"confirmed","note":"another defect"}]}\n' "$sb" "$f1" "$sid" > "$sp/verifiers/$sb.json"
sf=$(bash "$findings" resolve "$sp")
check "resolve: a member verdict splits that member into its own finding after its cluster" "$(q "$sf" '(.findings | length) == '"$sn"' + 1 and ([.findings[].id] | index("'"$sid"'")) == ([.findings[].id] | index("'"$f1"'")) + 1 and (.findings[] | select(.id == "'"$sid"'") | .split_from == "'"$f1"'" and .sources == 1 and .hunters == ["'"$sh"'"] and .verdict == "confirmed" and .surviving)')"
check "resolve: the split cluster is rebuilt from the members it keeps" "$(q "$sf" '.findings[] | select(.id == "'"$f1"'") | (.members | length) == '"$sk"' and all(.members[]; .id != "'"$sid"'") and .sources == (.hunters | length) and .hunters == ([.members[].hunter_id] | unique)')"
check "resolve: nothing dropped by a split, counts follow it" "$(q "$sf" '([.findings[].members[]] | length) == 8 and .counts.findings == (.findings | length) and .counts.surviving == 2')"
printf '{"groups":[{"id":"G1","kind":"root-cause","title":"t","root_cause":"r","fix_direction":"f","members":["%s","%s"]}],"links":[]}\n' "$f1" "$sid" > "$sp/analysis.json"
sa=$(bash "$findings" analyze "$sp")
check "analyze: a split finding can be a group member" "$(q "$sa" '(.findings[] | select(.id == "'"$sid"'") | .group) == "G1"')"

an="$tmp/an"; mkdir -p "$an"
cat > "$an/final.json" <<'J'
{"findings":[
 {"id":"F1","severity":"low","verdict":"confirmed","surviving":true,"file":"a.js","line":1},
 {"id":"F2","severity":"high","verdict":"refined","surviving":true,"file":"b.js","line":2},
 {"id":"F3","severity":"medium","verdict":"pre-existing","surviving":true,"file":"c.js","line":3},
 {"id":"F4","severity":"critical","verdict":"rejected","surviving":false,"file":"d.js","line":4},
 {"id":"F5","severity":"medium","verdict":"confirmed","surviving":true,"file":"e.js","line":5},
 {"id":"F6","severity":"low","verdict":"unverified","surviving":false,"file":"f.js","line":6}],
 "counts":{"findings":6}}
J
cat > "$an/analysis.json" <<'J'
{"groups":[
 {"id":"G1","kind":"root-cause","title":"t","root_cause":"r","fix_direction":"d","members":["F1","F2"]},
 {"id":"G2","kind":"duplicate","title":"t","root_cause":"r","fix_direction":"d","members":["F3","F5"],"keep":"F3"}],
 "links":[{"from":"G1","to":"G2","note":"n","order":"before"}]}
J
a=$(bash "$findings" analyze "$an")
check "analyze: valid input is written to analyzed.json" "$([ -f "$an/analyzed.json" ]; echo $?)"
check "analyze: group severity is the max member severity" "$(q "$a" '(.groups[] | select(.id == "G1") | .severity) == "high"')"
check "analyze: duplicate folds into the kept finding" "$(q "$a" '(.findings[] | select(.id == "F5") | .folded_into) == "F3" and (.findings[] | select(.id == "F3") | .also_reported_as[0].id) == "F5" and .counts.folded == 1 and .counts.groups == 2')"
check "analyze: findings carry their group" "$(q "$a" '(.findings[] | select(.id == "F1") | .group) == "G1" and (.findings[] | select(.id == "F6") | .group) == null')"
try() { printf '%s\n' "$1" > "$an/analysis.json"; bash "$findings" analyze "$an"; }
g='"kind":"pattern","title":"t","root_cause":"r","fix_direction":"d"'
o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F2"]},{"id":"G2",'"$g"',"members":["F2","F3"]}]}')
check "analyze: a finding in two groups is rejected" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("F2 is in more than one group"))')"
o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F9"]}]}')
check "analyze: unknown id is rejected" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("F9"))')"
o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F4"]}]}')
check "analyze: rejected finding cannot be grouped" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("F4"))')"
o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F2"]}],"links":[{"from":"G1","to":"F8","note":"n","order":"before"}]}')
check "analyze: unknown link endpoint is rejected" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("F8"))')"
o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F2"]}],"links":[{"from":"G1","to":"F3","note":"n","order":"later"}]}')
check "analyze: bad link order is rejected" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("bad order"))')"

o=$(try '{"groups":[{"id":"G1","kind":"a\"b\\c","title":"t","root_cause":"r","fix_direction":"d","members":["F1","F2"]}]}')
check "analyze: error detail with quotes and backslashes stays valid JSON" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("bad kind"))')"

o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F1","F2"]}]}')
check "analyze: a member listed twice in one group has its own error" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("F1 is listed twice in G1")) and (.detail | contains("more than one group") | not)')"
sed -e 's/"id":"F1","severity":"low"/"id":"F1"/' -e 's/"id":"F5","severity":"medium"/"id":"F5"/' "$an/final.json" > "$an/final.tmp" && mv "$an/final.tmp" "$an/final.json"
o=$(try '{"groups":[{"id":"G1",'"$g"',"members":["F1","F5"]}]}')
check "analyze: a member with no severity counts as low in group severity" "$(q "$o" '(.groups[0].severity) == "low"')"

bad() { # name, analysis json, detail substring
  o=$(try "$2")
  check "analyze: $1" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("'"$3"'"))')"
}
gd='"title":"t","root_cause":"r","fix_direction":"d"'
bad "keep must be a member" '{"groups":[{"id":"G1","kind":"duplicate",'"$gd"',"members":["F1","F2"],"keep":"F3"}]}' "keep must be a member"
bad "keep on a non-duplicate group is rejected" '{"groups":[{"id":"G1","kind":"pattern",'"$gd"',"members":["F1","F2"],"keep":"F1"}]}' "keep is only for duplicate"
bad "suspects on a non-pattern group is rejected" '{"groups":[{"id":"G1","kind":"root-cause",'"$gd"',"members":["F1","F2"],"suspects":[{"location":"x:1","note":"n"}]}]}' "suspects are only for pattern"
bad "suspects must be {location, note} objects" '{"groups":[{"id":"G1","kind":"pattern",'"$gd"',"members":["F1","F2"],"suspects":["x:1"]}]}' "suspects must be an array"
bad "a folded duplicate cannot be linked" '{"groups":[{"id":"G1","kind":"duplicate",'"$gd"',"members":["F2","F3"],"keep":"F2"}],"links":[{"from":"G1","to":"F3","note":"n","order":"before"}]}' "is a folded duplicate"
bad "a link cannot join an id to itself" '{"links":[{"from":"F1","to":"F1","note":"n","order":"before"}]}' "to itself"
bad "keep must be a string" '{"groups":[{"id":"G1","kind":"duplicate",'"$gd"',"members":["F1","F2"],"keep":["F1"]}]}' "keep must be a string"
bad "kind must be a string" '{"groups":[{"id":"G1","kind":["pattern"],'"$gd"',"members":["F1","F2"]}]}' "kind must be a string"
bad "link order must be a string" '{"links":[{"from":"F1","to":"F2","note":"n","order":["before"]}]}' "order must be a string"
o=$(try '{"groups":[{"id":"G1","kind":"duplicate",'"$gd"',"members":["F1","F2"],"keep":"F3"}],"links":[{"from":"G1","to":"F2","note":"n","order":"before"}]}')
check "analyze: a bad keep does not add a folded-duplicate error" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("keep must be a member")) and (.detail | contains("folded duplicate") | not)')"
o=$(try '{"groups":[{"id":"G1","kind":"root-cause",'"$gd"',"members":["F1","F2"],"keep":null,"suspects":[]},{"id":"G2","kind":"pattern",'"$gd"',"members":["F3","F5"],"suspects":null}]}')
check "analyze: null keep and null or empty suspects count as absent" "$(q "$o" '.counts.groups == 2')"
bad "a link needs a note" '{"links":[{"from":"F1","to":"F2","order":"before"}]}' "missing note"
bad "a group needs title, root_cause and fix_direction" '{"groups":[{"id":"G1","kind":"pattern","title":"t","members":["F1","F2"]}]}' "G1: missing root_cause"
bad "a group needs >= 2 members" '{"groups":[{"id":"G1","kind":"pattern",'"$gd"',"members":["F1"]}]}' "needs >= 2 members"
bad "group id must look like G<number>" '{"groups":[{"id":"X1","kind":"pattern",'"$gd"',"members":["F1","F2"]}]}' "bad group id X1"
bad "group ids are unique" '{"groups":[{"id":"G1","kind":"pattern",'"$gd"',"members":["F1","F2"]},{"id":"G1","kind":"pattern",'"$gd"',"members":["F3","F5"]}]}' "duplicate group id G1"
bad "members must be an array of strings" '{"groups":[{"id":"G1","kind":"pattern",'"$gd"',"members":"F1F2"}]}' "members must be an array of strings"
bad "groups must be an array" '{"groups":{"id":"G1"}}' "groups must be an array"
bad "links must be an array" '{"links":"none"}' "links must be an array"
bad "a group must be an object" '{"groups":["G1"]}' "a group is not an object"
printf '[1]\n' > "$an/analysis.json"
o=$(bash "$findings" analyze "$an")
check "analyze: a non-object analysis.json is rejected" "$(q "$o" '.error == "invalid_analysis" and (.detail | contains("not a JSON object"))')"
rm "$an/analysis.json"
o=$(bash "$findings" analyze "$an")
check "analyze: a missing analysis.json is an error" "$(q "$o" '.error == "no_analysis"')"
mkdir -p "$tmp/empty"; echo '{}' > "$tmp/empty/analysis.json"
o=$(bash "$findings" analyze "$tmp/empty")
check "analyze: no final.json is an error" "$(q "$o" '.error == "no_final"')"

# Surviving F ids come from the files above.
pl="$tmp/pipeline"; mkdir -p "$pl/hunters" "$pl/verifiers"
cp "$run/hunters/h1.json" "$run/hunters/h2.json" "$pl/hunters/"
# Stray files: neither is named after its own hunter_id or a batch id, so neither may add findings,
# verdicts or a timing row.
echo '{"hunter_id":"h1","lens":"logic","findings":[{"file":"z/z.js","line":1,"severity":"high","title":"retry"}]}' > "$pl/hunters/h1.retry.json"
pm=$(bash "$findings" merge "$pl")
check "merge: a stray hunter file with findings changes nothing" "$(q "$pm" '([.findings[] | select(.file == "z/z.js")] | length) == 0 and .counts.findings == 3 and .ignored == ["hunters/h1.retry.json"]')"
ids=$(jq -r '[.findings[] | select(.line == 10 or .line == 14) | .id] | join(" ")' "$pl/merged.json")
read -r pa pb <<< "$ids"
for b in $(jq -r '.batches[].id' "$pl/merged.json"); do
  jq -c --arg b "$b" '(.batches[] | select(.id == $b)) as $batch | {batch_id: $b, verdicts: [.findings[] | select(.id as $i | $batch.finding_ids | index($i)) | {id, verdict: "confirmed", note: "real"}]}' "$pl/merged.json" > "$pl/verifiers/$b.json"
done
jq -nc --arg a "$pa" '{batch_id: "B1", verdicts: [{id: $a, verdict: "rejected", note: "stray"}]}' > "$pl/verifiers/B1.input.json"
pr=$(bash "$findings" resolve "$pl")
check "resolve: a stray verifier file with verdicts changes nothing" "$(q "$pr" '(.findings[] | select(.id == "'"$pa"'") | .verdict) == "confirmed" and .counts.surviving == 3 and .ignored == ["hunters/h1.retry.json","verifiers/B1.input.json"]')"
jq -nc --arg a "$pa" --arg b "$pb" '{groups:[{id:"G1",kind:"duplicate",title:"t",root_cause:"r",fix_direction:"d",members:[$a,$b],keep:$a}],links:[]}' > "$pl/analysis.json"
pa_out=$(bash "$findings" analyze "$pl")
check "pipeline: merge, resolve and analyze compose; a duplicate folds out" "$(q "$pa_out" '.counts.groups == 1 and .counts.folded == 1 and ([.findings[] | select(.folded_into)] | length) == 1 and (.groups[0].folded | length) == 1')"
check "pipeline: group severity is the max member severity (critical and high members)" "$(q "$pa_out" '.groups[0].severity == "critical"')"
check "pipeline: analyzed.json is written and matches the output" "$(jq -e --argjson o "$pa_out" '. == $o' "$pl/analyzed.json" >/dev/null; echo $?)"
echo '{"groups":[],"links":[]}' > "$pl/analysis.json"
pe=$(bash "$findings" analyze "$pl")
check "pipeline: an empty analysis passes through with no groups or folds" "$(q "$pe" '.counts.groups == 0 and .counts.folded == 0 and .groups == [] and .links == [] and ([.findings[] | select(.group != null or .folded_into != null)] | length) == 0')"

check "timing: merge, resolve and analyze stamp script rows and per-file rows" "$(jq -se '[.[] | select(.by == "script") | .step] == ["merge","resolve","analyze","analyze"] and ([.[] | select(.step == "hunter") | .label] == ["h1","h2"]) and ([.[] | select(.step == "verifier")] | length) > 0' "$pl/timing.jsonl" >/dev/null; echo $?)"
mk=$(bash "$findings" mark "$pl" report)
check "timing: only <hunter_id>.json and <batch_id>.json files become agent rows" "$(jq -se --slurpfile m "$pl/merged.json" '([.[] | select(.step == "verifier") | .label] | sort) == ([$m[0].batches[].id] | sort)' "$pl/timing.jsonl" >/dev/null; echo $?)"
check "timing: mark appends and prints an agent row" "$(q "$mk" '.step == "report" and .label == "" and .by == "agent" and .start == .end')"
check "timing: mark with a label" "$(bash "$findings" mark "$pl" hunter h9 >/dev/null; jq -se '.[-1] | .step == "hunter" and .label == "h9"' "$pl/timing.jsonl" >/dev/null; echo $?)"
o=$(bash "$findings" mark "$pl")
check "timing: mark with no step is an error" "$(q "$o" '.error == "missing_step"')"
ti=$(bash "$init" | jq -r .run_dir)
check "timing: hunt-init.sh writes an init row" "$(jq -se '.[-1] | .step == "init" and .by == "script" and .end >= .start' "$ti/timing.jsonl" >/dev/null; echo $?)"

tm="$tmp/timing"; mkdir -p "$tm"
cat > "$tm/timing.jsonl" <<'J'
{"step":"init","label":"","by":"script","start":0,"end":0.5}
{"step":"hunt","label":"","by":"agent","start":10,"end":10}
{"step":"hunter","label":"h1","by":"agent","start":100,"end":100}
{"step":"hunter","label":"h2","by":"agent","start":110,"end":110}
{"step":"hunter","label":"h3","by":"agent","start":160,"end":160}
{"step":"merge","label":"","by":"script","start":165,"end":165.25}
{"step":"verify","label":"","by":"agent","start":170,"end":170}
{"step":"verifier","label":"B1","by":"agent","start":200,"end":200}
{"step":"verifier","label":"B2","by":"agent","start":230,"end":230}
{"step":"hunter","label":"h3","by":"agent","start":160,"end":160}
{"step":"resolve","label":"","by":"script","start":231,"end":231.25}
{"step":"report","label":"","by":"agent","start":300,"end":300}
J
t=$(bash "$findings" timing "$tm")
check "timing: hunter spread and verify sum from the marks" "$(q "$t" '.pipeline == {hunter_spread: 60, verify_sum: 90, verify_wall: 60}')"
check "timing: per-step durations, rerun rows deduped" "$(q "$t" '([.steps[] | select(.step == "hunter") | .duration] == [90, 100, 150]) and ([.steps[] | select(.step == "merge") | .duration] == [0.3])')"
check "timing: a mark runs from the row that ended before it" "$(q "$t" '([.steps[] | select(.step == "hunt" or .step == "report") | .duration] == [9.5, 68.8])')"
check "timing: script and agent split the wall time" "$(q "$t" '.wall == 300 and .script == 1 and .agent == 299')"
cat > "$tm/timing.jsonl" <<'J'
{"step":"hunt","label":"","by":"agent","start":10,"end":10}
{"step":"hunter","label":"h1","by":"agent","start":100,"end":100}
{"step":"hunt","label":"","by":"agent","start":200,"end":200}
{"step":"hunter","label":"h2","by":"agent","start":300,"end":300}
{"step":"verify","label":"","by":"agent","start":310,"end":310}
{"step":"verifier","label":"B1","by":"agent","start":320,"end":320}
{"step":"verify","label":"","by":"agent","start":330,"end":330}
{"step":"verifier","label":"B2","by":"agent","start":400,"end":400}
J
t=$(bash "$findings" timing "$tm")
check "timing: a second hunt or verify mark before a retry never makes a duration negative" "$(q "$t" '[.steps[] | select(.step == "hunter" or .step == "verifier") | .duration] == [90, 290, 10, 90]')"
printf '%s\n' '{"step":"merge","label":"","by":"script","start":5,"end":6}' > "$tm/timing.jsonl"
t=$(bash "$findings" timing "$tm")
check "timing: missing marks give null, not an error" "$(q "$t" '.wall == 1 and .pipeline == {hunter_spread: null, verify_sum: null, verify_wall: null}')"
o=$(bash "$findings" timing "$tmp/empty")
check "timing: no timing.jsonl is an error" "$(q "$o" '.error == "no_timing"')"

exit $fail
