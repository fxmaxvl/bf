#!/usr/bin/env bash
# Smoke test for fetch-pr-comments.sh and wait-for-review.sh against a stub `gh` on PATH.
#
# Usage: pr-comments-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fetch=$here/fetch-pr-comments.sh
wait=$here/wait-for-review.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# Stub gh: answers only the calls the two scripts make. The PR number echoes the graphql `num`
# argument; the newest bot review sits on BOT_SHA with one open bot thread.
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") echo "o/r" ;;
  "pr view") echo 1 ;;
  "api graphql")
    num=0
    for a in "$@"; do case "$a" in num=*) num=${a#num=} ;; esac; done
    cat <<JSON
{"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
 "number":$num,"url":"https://github.com/o/r/pull/$num","title":"t","headRefOid":"$BOT_SHA",
 "baseRefName":"main","headRefName":"feat","commits":{"nodes":[{"commit":{"oid":"$BOT_SHA"}}]},
 "files":{"totalCount":0,"nodes":[]},"comments":{"nodes":[]},
 "reviews":{"totalCount":1,"nodes":[{"author":{"login":"bot","__typename":"Bot"},"body":"",
   "state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","commit":{"oid":"$BOT_SHA"}}]},
 "reviewThreads":{"nodes":[{"id":"T1","isResolved":false,"isOutdated":false,"path":"a","line":1,
   "originalLine":1,"diffSide":"RIGHT","comments":{"nodes":[{"databaseId":1,
   "author":{"login":"bot","__typename":"Bot"},"body":"fix","createdAt":"x","diffHunk":""}]}}]}
}}}}
JSON
    ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:/bin:$PATH" BOT_SHA=abc1234
url=https://github.com/o/r/pull/125

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }
field() { jq -r "$1" 2>/dev/null <<<"$2"; }

out=$(bash "$fetch" "125 --wait")
eq 'fetch "125 --wait" resolves PR 125' "$(field .pr "$out")" 125

out=$(bash "$fetch" "125 --timout 600")
eq "fetch unknown flag --timout -> bad_args" "$(field .error "$out")" bad_args

out=$(bash "$wait" "$url" --timout 600)
eq "wait unknown flag --timout -> bad_args" "$(field .error "$out")" bad_args

out=$(bash "$wait" "$url" --wait --timeout 0 --interval 1)
eq "wait <url> --wait accepted" "$(field .status "$out")" findings

out=$(bash "$wait" "$url" --head)
eq "wait --head with no value -> bad_args" "$(field .error "$out")" bad_args

out=$(bash "$wait" "$url" --head "$BOT_SHA" --timeout 0 --interval 1)
eq "wait --head <bot sha> -> review_landed" "$(field .status "$out")" review_landed

out=$(bash "$wait" "$url" --head fff0000 --timeout 0 --interval 1)
eq "wait --head <other sha> -> timeout" "$(field .status "$out")" timeout

[ "$fails" -eq 0 ]
