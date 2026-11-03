#!/usr/bin/env bash
# Smoke test for init-probe.sh's state_matches against a throwaway repo with a fixture state.
#
# Usage: init-probe-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

repo=$tmp/repo
mkdir -p "$repo" "$tmp/home"
git -C "$repo" init -q
probe() { (cd "$repo" && bash "$dir/init-probe.sh" "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_matches"])'); }

eq "no state -> null" "$(probe 'add dark mode')" None
(cd "$repo" && HOME=$tmp/home bash "$dir/state-ops.sh" --init --slug dark-mode --idea 'add dark mode' --mode quick >/dev/null)
eq "empty args resume" "$(probe '')" True
eq "same idea and mode resume" "$(probe '--quick add dark mode')" True
eq "foreign idea" "$(probe '--quick fix login bug')" False
eq "same idea, other mode" "$(probe 'add dark mode')" False
eq "gh issue not in state" "$(probe '--quick GH-ISSUE:7 add dark mode')" False
(cd "$repo" && bash "$dir/state-ops.sh" mode=review >/dev/null)
eq "review leftover, empty args" "$(probe '')" False

archived=$(cd "$repo" && bash "$dir/state-ops.sh" --archive)
case ${archived#"$repo"/} in .bf/sessions/archive/*T*-dark-mode-build-state.json) moved=yes ;; *) moved=$archived ;; esac
eq "archive moves the state" "$moved" yes
eq "no state after archive" "$(probe 'fix login bug')" None

[ "$fails" -eq 0 ]
