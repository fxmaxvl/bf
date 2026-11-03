#!/usr/bin/env bash
# Smoke test for state-ops.sh's config flag resolution against a throwaway HOME and repo.
#
# Usage: state-ops-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state-ops.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

key=parallel_audit
flag() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$key"; }

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

key=auto_fix_style
eq "auto_fix_style: no config -> default off" "$(resolve afs-none - | tr '\n' ' ')" "False False "
eq "auto_fix_style: explicit true opts in" "$(resolve afs-on '{"auto_fix_style": true}' | tr '\n' ' ')" "True True "
eq "auto_fix_style: malformed config -> default off" "$(resolve afs-bad '{oops' | tr '\n' ' ')" "False False "
eq "auto_fix_style: read mode returns the init-time snapshot" "$(cd "$tmp/afs-on/repo" && HOME=$tmp/afs-none/home bash "$script" | flag)" True


repo=$tmp/baseline/repo home=$tmp/baseline/home
mkdir -p "$repo" "$home"
git -C "$repo" init -q
mkdir -p "$repo/.bf/x" && echo s > "$repo/stray one.md" && echo b > "$repo/.bf/x/b.md"
baseline=$(cd "$repo" && HOME=$home bash "$script" --init --slug t --idea x 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["paths"]["untracked_baseline"])')
eq "init writes the untracked baseline, .bf/ excluded" "$(tr '\0' '\n' < "$baseline")" "stray one.md"

pending() { (cd "$repo" && bash "$script" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pending_fixes"])'); }
(cd "$repo" && bash "$script" pending_fixes=C1,K2 >/dev/null)
eq "pending_fixes round-trips through read" "$(pending)" "C1,K2"
(cd "$repo" && bash "$script" pending_fixes=null >/dev/null)
eq "pending_fixes=null clears it" "$(pending)" None

archive() { (cd "$repo" && bash "$script" --archive); }
temp=$(cd "$repo" && bash "$script" | python3 -c 'import json,sys; print(json.load(sys.stdin)["paths"]["temp"])')
echo old > "$temp"
first=$(archive)
eq "archive moves the run's temp file with the state" "$(cat "${first%build-state.json}temp.md")" old
(cd "$repo" && HOME=$home bash "$script" --init --slug t --idea y >/dev/null)
eq "same-hour rerun starts without the old temp file" "$([ -e "$temp" ] && echo kept || echo gone)" gone
second=$(archive)
eq "second same-hour archive gets its own name" "$([ "$first" != "$second" ] && echo distinct || echo "reused $first")" distinct
idea() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["idea"])' "$1"; }
eq "both archived states survive" "$(idea "$first")$(idea "$second")" xy

echo '{bad' > "$repo/.bf/sessions/build-state.json"
eq "read of a corrupt state returns an error object" "$( (cd "$repo" && bash "$script" 2>&1 >/dev/null) |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["corrupt"])')" True
corrupt=$(archive)
eq "archive moves a corrupt state aside" "${corrupt##*/}:$(cat "$corrupt"):$([ -e "$repo/.bf/sessions/build-state.json" ] && echo left || echo moved)" "corrupt-build-state.json:{bad:moved"

[ "$fails" -eq 0 ]
