#!/usr/bin/env bash
# Smoke test for state-ops.sh's parallel_audit resolution against a throwaway HOME and repo.
#
# Usage: state-ops-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state-ops.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

flag() { python3 -c 'import json,sys; print(json.load(sys.stdin)["parallel_audit"])'; }

# $1 case name, $2 config.json contents ("-" for no file)
resolve() {
    local home=$tmp/$1/home repo=$tmp/$1/repo
    mkdir -p "$home/.bf" "$repo"
    git -C "$repo" init -q
    [ "$2" = "-" ] || printf '%s\n' "$2" > "$home/.bf/config.json"
    (cd "$repo" && HOME=$home bash "$script" --read-config 2>"$tmp/$1/err" | flag)
    (cd "$repo" && HOME=$home bash "$script" --init --slug t --idea x --mode quick 2>>"$tmp/$1/err" | flag)
}
warned() { grep -c 'Warning: could not read' "$tmp/$1/err" || true; }

eq "no config -> default on (read-config, init)" "$(resolve none - | tr '\n' ' ')" "True True "
eq "key absent -> default on" "$(resolve empty '{}' | tr '\n' ' ')" "True True "
eq "explicit false opts out" "$(resolve off '{"parallel_audit": false}' | tr '\n' ' ')" "False False "
eq "malformed config -> default on" "$(resolve bad '{oops' | tr '\n' ' ')" "True True "
eq "malformed config warns on each read" "$(warned bad)" 2
eq "readable config warns nothing" "$(warned none)$(warned empty)$(warned off)" "000"

[ "$fails" -eq 0 ]
