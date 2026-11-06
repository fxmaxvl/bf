#!/usr/bin/env bash
# Smoke test for session-untracked.sh against a throwaway repo.
#
# Usage: session-untracked-smoke.sh
# Output: one PASS/FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-untracked.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

mkdir "$tmp/repo" && cd "$tmp/repo"
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git commit -q --allow-empty -m base
list() { bash "$script" "$@" 2>/dev/null | tr '\0' '\n' | sort | paste -sd, -; }

mkdir -p .bf/sessions gen && echo s > .bf/sessions/s.md && echo a > a.txt && echo g > gen/g.txt
git init -q nested
eq "no baseline: every file listed, .bf/ and nested repo left out" "$(list)" "a.txt,gen/g.txt"
eq "a nested repo is noted on stderr" "$(bash "$script" 2>&1 >/dev/null | grep -c 'nested/')" 1

printf 'a.txt\0' > "$tmp/baseline"
eq "baseline entry left out" "$(list --baseline "$tmp/baseline")" "gen/g.txt"
printf 'gen/\0' > "$tmp/baseline"
eq "baseline entry ending in / covers the directory" "$(list --baseline "$tmp/baseline")" "a.txt"

echo n > "café.txt"
eq "a non-ASCII name is listed unquoted" "$(list --baseline "$tmp/baseline")" "a.txt,café.txt"

mkdir sub
eq "run from a subdirectory: paths stay repo-relative" "$(cd sub && list --baseline "$tmp/baseline")" "a.txt,café.txt"

rc=0; bash "$script" --baseline "$tmp/missing" >/dev/null 2>&1 || rc=$?
eq "a missing baseline file -> exit 1" "$rc" 1

[ "$fails" -eq 0 ]
