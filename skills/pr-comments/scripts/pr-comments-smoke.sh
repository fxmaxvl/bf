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
  "pr view")
    # reviews mirror the graphql stub: bot on BOT_SHA, an older bot2 review on old0000
    case " $* " in
      *" --json reviews "*)
        out='{"reviews":[{"author":{"login":"bot2"},"state":"COMMENTED","submittedAt":"2025-12-31T00:00:00Z","commit":{"oid":"old0000"}},
          {"author":{"login":"bot"},"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","commit":{"oid":"'"$BOT_SHA"'"}}]}'
        jqx=""; prev=""
        for a in "$@"; do [ "$prev" = --jq ] && jqx=$a; prev=$a; done
        if [ -n "$jqx" ]; then jq -r "$jqx" <<<"$out"; else echo "$out"; fi ;;
      *) echo 1 ;;
    esac ;;
  "api graphql")
    num=0
    for a in "$@"; do case "$a" in num=*) num=${a#num=} ;; esac; done
    cat <<JSON
{"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
 "number":$num,"url":"https://github.com/o/r/pull/$num","title":"t","headRefOid":"$BOT_SHA",
 "baseRefName":"main","headRefName":"feat","headRepository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"oid":"$BOT_SHA","committedDate":"2026-01-02T00:00:00Z"}}]},
 "files":{"totalCount":0,"nodes":[]},"comments":{"nodes":[{"author":{"login":"bot","__typename":"Bot"},
   "body":"No open findings.","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-03T00:00:00Z"},
   {"author":{"login":"me","__typename":"User"},"body":"my note","createdAt":"x","updatedAt":"x"},
   {"author":{"login":"me","__typename":"User"},"body":"Fixed in abc.\n\n<!-- bf:pr-comments -->","createdAt":"x","updatedAt":"x"}]},
 "reviews":{"totalCount":2,"nodes":[{"author":{"login":"bot2","__typename":"Bot"},"body":"",
   "state":"COMMENTED","submittedAt":"2025-12-31T00:00:00Z","commit":{"oid":"old0000"}},
   {"author":{"login":"bot","__typename":"Bot"},"body":"",
   "state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","commit":{"oid":"$BOT_SHA"}}]},
 "reviewThreads":{"nodes":[{"id":"T1","isResolved":false,"isOutdated":false,"path":"a","line":1,
   "originalLine":1,"diffSide":"RIGHT","comments":{"nodes":[{"databaseId":1,
   "author":{"login":"bot","__typename":"Bot"},"body":"fix","createdAt":"x","diffHunk":""}]}}]}
}}}}
JSON
    ;;
  "api repos/o/r/activity")
    # the head's push; NO_PUSH=1 leaves only an older push, so the push time is unknown
    if [ -n "${NO_PUSH:-}" ]; then echo '[{"activity_type":"push","after":"old0000","timestamp":"2025-12-30T00:00:00Z"}]'
    elif [ -n "${FIRST_PUSH:-}" ]; then echo '[{"activity_type":"branch_creation","after":"'"$BOT_SHA"'","timestamp":"2026-01-02T06:00:00Z"}]'
    else echo '[{"activity_type":"push","after":"'"$BOT_SHA"'","timestamp":"2026-01-02T05:00:00Z"}]'; fi ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:/bin:$PATH" BOT_SHA=abc1234
url=https://github.com/o/r/pull/125

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }
field() { jq -r "$1" 2>/dev/null <<<"$2"; }

out=$(printf '%s' '125 --wait' | bash "$fetch")
eq 'fetch "125 --wait" resolves PR 125' "$(field .pr "$out")" 125

eq "fetch reports the head push time, not the commit time" "$(field .head_pushed_at "$out")" 2026-01-02T05:00:00Z
eq "fetch reports no push time when the log lacks the head" "$(NO_PUSH=1 bash "$fetch" <<<"125" | jq -r .head_pushed_at)" null
eq "fetch gives a PR-level post its edit time" "$(field '[.threads[] | select(.kind == "issue")][0].updated_at' "$out")" 2026-01-03T00:00:00Z

eq "fetch drops the viewer's own PR-level comment" "$(field '[.threads[] | select(.author == "me")] | length' "$out")" 0
eq "fetch notes the dropped own comment" "$(field '[.notes[] | select(test("by me skipped"))] | length' "$out")" 1
out=$(printf '%s' '125 --all' | bash "$fetch")
eq "fetch --all keeps the viewer's own note but not the skill's marked reply" "$(field '[.threads[] | select(.author == "me")] | length' "$out")" 1
eq "fetch takes a branch's first push (branch_creation) as the push time" "$(FIRST_PUSH=1 bash "$fetch" <<<"125" | jq -r .head_pushed_at)" 2026-01-02T06:00:00Z

out=$(printf '%s' '125 --timout 600' | bash "$fetch")
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

out=$(bash "$wait" "$url" --head "$BOT_SHA" --bot bot2 --timeout 0 --interval 1)
eq "wait --head --bot <bot that has not reviewed head> -> timeout" "$(field .status "$out")" timeout

out=$(bash "$wait" "$url" --head "$BOT_SHA" --bot bot --timeout 0 --interval 1)
eq "wait --head --bot <bot that reviewed head> -> review_landed" "$(field .status "$out")" review_landed

out=$(bash "$wait" "$url" --bot bot)
eq "wait --bot without --head -> bad_args" "$(field .error "$out")" bad_args

[ "$fails" -eq 0 ]
