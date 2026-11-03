#!/usr/bin/env bash
# Smoke check for pr-review-payload.sh on a fixture diff. Never calls GitHub.
#
# Usage: pr-review-payload-smoke.sh
# Contract: exits 0 when every case passes, 1 otherwise; prints one PASS/FAIL line per case.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
build="$here/pr-review-payload.sh"
command -v jq >/dev/null || { echo "FAIL jq is required"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # name, condition-exit-status
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}

cat > "$tmp/diff" <<'DIFF'
diff --git a/src/a.ts b/src/a.ts
index 1111111..2222222 100644
--- a/src/a.ts
+++ b/src/a.ts
@@ -10,4 +10,5 @@ function f() {
 const a = 1;
-const b = 2;
+const b = 3;
+const c = 4;
--- not a header, a removed line
 return a;
@@ -40,2 +41,2 @@
 x();
+y();
diff --git a/gone.ts b/gone.ts
deleted file mode 100644
--- a/gone.ts
+++ /dev/null
@@ -1 +0,0 @@
-bye
DIFF

cat > "$tmp/findings.json" <<'JSON'
[{"id":"C1","label":"critical","path":"src/a.ts","line":11,"text":"added line"},
 {"id":"C2","label":"must-fix","path":"src/a.ts","line":10,"text":"context line"},
 {"id":"C3","label":"must-fix","path":"src/a.ts","line":30,"text":"outside any hunk"},
 {"id":"X1","label":"must-fix","path":"src/other.ts","line":3,"text":"file not in diff"},
 {"id":"Y1","label":"should-consider","path":null,"line":null,"text":"spec section"},
 {"id":"C4","label":"should-consider","path":"src/a.ts","line":"10-12","text":"range in one hunk"},
 {"id":"C5","label":"should-consider","path":"src/a.ts","line":"12-42","text":"range across hunks"},
 {"id":"C6","label":"must-fix","path":"src/a.ts","line":13,"text":"line after the removed --- line"}]
JSON

out=$(bash "$build" "$tmp/findings.json" "$tmp/diff" abc123 REQUEST_CHANGES)
inline() { jq -e --arg id "$1" '.comments | map(select(.body | startswith("**\($id)**"))) | length == 1' <<< "$out" >/dev/null; }
in_body() { jq -e --arg id "$1" '.body | contains("**\($id)**")' <<< "$out" >/dev/null; }

ok=0; jq -e '.commit_id == "abc123" and .event == "REQUEST_CHANGES"' <<< "$out" >/dev/null || ok=1
check "commit_id and event carried through" $ok
ok=0; inline C1 && jq -e '.comments[] | select(.body | startswith("**C1**")) | .line == 11 and .side == "RIGHT"' <<< "$out" >/dev/null || ok=1
check "added line goes inline on the RIGHT side" $ok
ok=0; inline C2 || ok=1
check "context line goes inline" $ok
ok=0; in_body C3 && ! inline C3 || ok=1
check "line outside any hunk goes to the body" $ok
ok=0; in_body X1 && ! inline X1 || ok=1
check "file not in the diff goes to the body" $ok
ok=0; in_body Y1 && ! inline Y1 || ok=1
check "finding without a line goes to the body" $ok
ok=0; jq -e '.comments[] | select(.body | startswith("**C4**")) | .start_line == 10 and .line == 12' <<< "$out" >/dev/null || ok=1
check "range in one hunk anchors start_line..line" $ok
ok=0; in_body C5 && ! inline C5 || ok=1
check "range across hunks goes to the body" $ok
ok=0; inline C6 && jq -e '.comments[] | select(.body | startswith("**C6**")) | .line == 13' <<< "$out" >/dev/null || ok=1
check "removed line starting with --- is not read as a header" $ok
ok=0; jq -e '.body | startswith("bf:review: 8 finding(s), 4 inline.")' <<< "$out" >/dev/null || ok=1
check "body counts findings and inline comments" $ok

err=$(bash "$build" "$tmp/findings.json" "$tmp/diff" abc123 APPROVE); rc=$?
ok=0; [ $rc = 1 ] && jq -e '.error == "bad_event"' <<< "$err" >/dev/null || ok=1
check "rejects an event other than COMMENT or REQUEST_CHANGES" $ok

exit $fail
