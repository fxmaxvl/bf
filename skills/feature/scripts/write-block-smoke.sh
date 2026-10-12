#!/usr/bin/env bash
# Smoke test for write-block.sh: usage errors, create, append, in-place replace, header prefix,
# rejected body, and concurrent writers. The race window is too narrow to hit at normal speed, so
# the lock is proven on slowed copies of the script: intact with the lock, corrupted without it.
#
# Usage: write-block-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$dir/write-block.sh
read_block=$dir/read-block.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

usage() { local rc=0; bash "$script" "$@" </dev/null 2>"$tmp/err" || rc=$?; echo "$rc $(head -n1 "$tmp/err")"; }
eq "no file argument exits 1" "$(usage)" "1 Usage: write-block.sh <file> --block <header> < content"
eq "missing --block exits 1" "$(usage "$tmp/u.md")" "1 Error: --block <header> is required"
eq "empty header exits 1" "$(usage "$tmp/u.md" --block "")" "1 Error: --block requires a header argument"

f=$tmp/sub/t.md
printf 'spec v1\n' | bash "$script" "$f" --block "## Spec"
eq "missing file and directory created" "$(cat "$f")" "$(printf '## Spec\n\nspec v1')"

printf 'long v1\n### sub\nx\n' | bash "$script" "$f" --block "## Specification"
printf 'c1\n' | bash "$script" "$f" --block "## Complexity Report"
eq "absent header appended after a blank line" "$(cat "$f")" "$(printf '## Spec\n\nspec v1\n\n## Specification\n\nlong v1\n### sub\nx\n\n## Complexity Report\n\nc1')"

before=$(bash "$read_block" "$f" --block "## Specification")
printf 'spec v2\nline2\n' | bash "$script" "$f" --block "## Spec"
eq "existing block replaced in place" "$(bash "$read_block" "$f" --block "## Spec")" "$(printf '\nspec v2\nline2\n')"
eq "prefix header untouched" "$(bash "$read_block" "$f" --block "## Specification")" "$before"
eq "block order kept" "$(grep '^## ' "$f" | tr '\n' '|')" "## Spec|## Specification|## Complexity Report|"

cp "$f" "$tmp/pre"
rc=0; printf 'a\n## evil\n' | bash "$script" "$f" --block "## Spec" 2>"$tmp/err" || rc=$?
eq "body with a ## line rejected" "$rc $(cat "$tmp/err")" "1 Error: block body contains a '## ' line, which would split the block"
eq "rejected write leaves file unchanged" "$(cmp -s "$f" "$tmp/pre" && echo same)" same

w=$tmp/ws.md
printf '## Spec  \n\nold\n\n## Plan\n\np\n' > "$w"
printf 'new\n' | bash "$script" "$w" --block "## Spec" 2>"$tmp/err"
eq "header with trailing whitespace replaced in place" "$(cat "$w")" "$(printf '## Spec\n\nnew\n\n## Plan\n\np')"
eq "successful write prints nothing to stderr" "$(cat "$tmp/err")" ""

r=$tmp/race.md
printf '## QA\n\nqa\n' > "$r"
for name in "Complexity Report" "Consistency Report" "Implementation Review"; do
    ( for i in $(seq 1 20); do printf '%s\nrun %s\n' "$name" "$i" | bash "$script" "$r" --block "## $name"; done ) &
done
wait
eq "concurrent writers keep one header each" "$(grep '^## ' "$r" | sort | tr '\n' '|')" "## Complexity Report|## Consistency Report|## Implementation Review|## QA|"
eq "concurrent writers keep each final body" "$(bash "$read_block" "$r" --block "## Consistency Report")" "$(printf '\nConsistency Report\nrun 20\n')"

sed "s/^    lines = f.read().splitlines(keepends=True)$/&\\
    __import__('time').sleep(0.1)/" "$script" > "$tmp/slow.sh"
sed 's/^    fcntl.flock(f, fcntl.LOCK_EX)$/    pass/' "$tmp/slow.sh" > "$tmp/slow-nolock.sh"
eq "slowed copies built" "$(grep -c 'sleep(0.1)' "$tmp/slow.sh") $(grep -c 'LOCK_EX' "$tmp/slow-nolock.sh")" "1 0"

# The lockless case is probabilistic: it needs two of the 24 slowed writes to overlap, which a
# 0.1s read-to-write window makes near-certain but not guaranteed on a heavily loaded machine.
slow_race() {
    printf '## QA\n\nqa\n' > "$2"
    for name in A B C; do
        ( for i in $(seq 1 8); do printf 'run %s\n' "$i" | bash "$1" "$2" --block "## $name"; done ) &
    done
    wait
    grep '^## ' "$2" | sort | tr '\n' '|'
}
eq "slowed writers with the lock stay intact" "$(slow_race "$tmp/slow.sh" "$tmp/slow.md")" "## A|## B|## C|## QA|"
lockless=$(slow_race "$tmp/slow-nolock.sh" "$tmp/slow-nolock.md")
eq "slowed writers without the lock corrupt the file" "$([ "$lockless" != "## A|## B|## C|## QA|" ] && echo corrupted)" corrupted

[ "$fails" -eq 0 ]
