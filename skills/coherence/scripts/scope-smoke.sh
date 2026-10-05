#!/usr/bin/env bash
# Smoke check for scope.sh untracked-file and quoted-name handling, run against a throwaway repo.
#
# Usage: scope-smoke.sh
# Contract: exits 0 when every case passes, 1 otherwise; prints one PASS/FAIL line per case.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
scope="$here/scope.sh"
command -v jq >/dev/null || { echo "FAIL jq is required"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # name, condition-exit-status
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}
has()  { jq -e --arg f "$2" '.files | index($f) != null' <<< "$1" >/dev/null; }
mode() { jq -r .mode <<< "$1"; }

new_repo() {
  rm -rf "$tmp/r"; mkdir "$tmp/r"; cd "$tmp/r" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo base > a.txt; echo ignored.log > .gitignore
  git add . && git commit -qm init
}

new_repo
echo change >> a.txt
echo n > n.txt; echo s > "sp ace.txt"; echo e > "é.txt"
mkdir .bf; echo x > .bf/x.md; echo i > ignored.log
out=$(bash "$scope" --with-diff --with-untracked)
ok=0
[ "$(mode "$out")" = working ] || ok=1
for f in a.txt n.txt "sp ace.txt" "é.txt"; do has "$out" "$f" || ok=1; done
has "$out" .bf/x.md && ok=1
has "$out" ignored.log && ok=1
check "working: tracked + untracked, skips .bf and ignored" $ok

ok=0; jq -e --arg f n.txt '.whitespace_only_files | index($f) == null' <<< "$out" >/dev/null || ok=1
check "working: new text file is not whitespace-only" $ok

new_repo; echo n > n.txt
out=$(bash "$scope" --with-diff --with-untracked)
ok=0; [ "$(mode "$out")" = working ] && has "$out" n.txt || ok=1
check "working: untracked-only tree" $ok

out=$(bash "$scope" --with-diff)
ok=0; [ "$(mode "$out")" = branch ] || ok=1
check "without --with-untracked: untracked-only tree falls to branch" $ok

mkdir .bf; echo x > .bf/x.md
out=$(bash "$scope" --with-diff --with-untracked n.txt)
ok=0; [ "$(mode "$out")" = paths ] && has "$out" n.txt || ok=1
check "paths: names an untracked file" $ok

out=$(bash "$scope" --with-diff --with-untracked .)
ok=0; has "$out" .bf/x.md && ok=1; has "$out" n.txt || ok=1
check "paths: '.' skips .bf" $ok

# git C-quotes these names in the `diff --git` header even with core.quotePath=false.
new_repo
tab=$(printf 't\tab.txt'); ctl=$(printf 'c\001tl.txt'); nl=$(printf 'n\nl.txt')
echo q > 'q"x.txt'; git add . && git commit -qm quoted
echo change >> 'q"x.txt'; echo t > "$tab"; echo c > "$ctl"; echo l > "$nl"; echo b > 'b\s.txt'
out=$(bash "$scope" --with-diff --with-untracked)
ok=0
for f in 'q"x.txt' "$tab" "$ctl" "$nl" 'b\s.txt'; do
  has "$out" "$f" || ok=1
  jq -e --arg f "$f" '[.hunks[] | select(.file == $f)] | length == 1' <<< "$out" >/dev/null || ok=1
  jq -e --arg f "$f" '.whitespace_only_files | index($f) == null' <<< "$out" >/dev/null || ok=1
done
jq -e '.file_count == (.files | length)' <<< "$out" >/dev/null || ok=1
check "working: quoted, tab, control-byte, newline and backslash names keep files, hunks and file_count" $ok

exit $fail
