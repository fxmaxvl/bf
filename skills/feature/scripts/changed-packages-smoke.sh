#!/usr/bin/env bash
# Smoke test for changed-packages.sh changed_files against a throwaway repo.
#
# Usage: changed-packages-smoke.sh
# Output: one PASS/FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

cd "$tmp"
git init -q -b base . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > tracked.txt && echo b > edited.txt
git add . && git commit -qm base
git checkout -q -b work
files() { bash "$dir/changed-packages.sh" --base base | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin)["changed_files"])))'; }

eq "no change -> empty" "$(files)" ""

echo c > committed.txt && git add committed.txt && git commit -qm c
eq "committed change listed" "$(files)" "committed.txt"

echo e >> edited.txt
echo n > untracked.txt
mkdir -p .bf/sessions && echo s > .bf/sessions/s.md
git init -q nested
eq "uncommitted and untracked listed, .bf/ and nested repo left out" "$(files)" "committed.txt,edited.txt,untracked.txt"

mkdir -p "$tmp/home"
HOME=$tmp/home bash "$dir/state-ops.sh" --init --slug s --idea x --mode quick >/dev/null 2>&1
eq "files untracked when state-ops.sh --init ran are left out" "$(files)" "committed.txt,edited.txt"
echo f > fresh.txt
eq "a file made after state-ops.sh --init is listed" "$(files)" "committed.txt,edited.txt,fresh.txt"

echo x > "café.txt"
git init -q "résumé"
eq "a non-ASCII name is listed unquoted and a non-ASCII nested repo is left out" "$(files)" "café.txt,committed.txt,edited.txt,fresh.txt"

[ "$fails" -eq 0 ]
