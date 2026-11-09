#!/usr/bin/env bash
# Smoke test for finalize-git.sh against a throwaway repo with a local bare remote and a stub gh.
#
# Usage: finalize-git-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/finalize-git.sh
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "${GH_LOG:-/dev/null}"
if [ -n "${GH_FAIL:-}" ]; then echo "HTTP 401: Bad credentials" >&2; exit 1; fi
state=${GH_PR_STATE:-}
if [ -n "${GH_LOOKUPS:-}" ] && [ "$1 $2" = "pr list" ]; then
  if [ -s "$GH_LOOKUPS" ]; then
    [ -z "${GH_FAIL_LOOKUP_AFTER:-}" ] || { echo "HTTP 502" >&2; exit 1; }
    state=${GH_PR_STATE_AFTER:-}
  fi
  echo x >> "$GH_LOOKUPS"
fi
case "$1 $2" in
  "pr create") [ -z "${GH_FAIL_CREATE:-}" ] || exit 4; echo "https://example.test/pr/1" ;;
  "pr edit") [ -z "${GH_FAIL_EDIT:-}" ] || exit 4 ;;
  "pr list") [ -z "$state" ] || echo "$state https://example.test/pr/9 ${GH_PR_HEAD:-0123abc} main" ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/repo"
cd "$tmp/repo"
git config commit.gpgsign false
git remote add origin "$tmp/origin.git"
echo base > base.txt
git add . && git commit -qm base

finalize() { bash "$script" --commit-msg "feat: x" --pr-title t --pr-body b "$@" >/dev/null 2>"$tmp/err"; }
head_sha() { git rev-parse HEAD; }
remote_sha() { git --git-dir="$tmp/origin.git" rev-parse --verify --quiet refs/heads/main || echo none; }

mkdir -p src .bf/reviews .bf/sessions
echo n > src/new.txt
echo stray > stray.md
echo r > .bf/reviews/r.md
echo s > .bf/sessions/s.md
before=$(head_sha)
rc=0; finalize --add src/new.txt || rc=$?
eq "unnamed untracked file -> exit 3" "$rc" 3
eq "unnamed untracked file -> listed" "$(grep -c '^  stray.md$' "$tmp/err")" 1
eq "unnamed untracked file -> no commit" "$(head_sha)" "$before"
eq "unnamed untracked file -> nothing pushed" "$(remote_sha)" none

finalize --add src/new.txt --leave-untracked
eq "named untracked file committed, stray left out" "$(git show --name-only --format= HEAD)" "src/new.txt"
eq "stray still untracked" "$(git ls-files --others --exclude-standard -- stray.md)" "stray.md"
eq "pushed" "$(remote_sha)" "$(head_sha)"
rm stray.md

mkdir -p lib/deep && echo d > lib/deep/d.txt
git rm -q --cached base.txt && rm base.txt
finalize --add lib/
eq "named directory and a tracked deletion staged" "$(git show --name-status --format= HEAD | sort | tr '\t' ' ' | paste -sd, -)" "A lib/deep/d.txt,D base.txt"

echo edit >> src/new.txt
finalize
eq "tracked edit staged without --add" "$(git show --name-only --format= HEAD)" "src/new.txt"

mv src/new.txt src/renamed.txt
rc=0; finalize || rc=$?
eq "plain mv -> new path needs --add" "$rc" 3
finalize --add src/renamed.txt
eq "rename committed with --add" "$(git show --name-status --format= HEAD | cut -f2- | tr '\t' ' ')" "src/new.txt src/renamed.txt"

echo abs > abs.txt
logical=${tmp#/private}
finalize --add "$logical/repo/abs.txt"
eq "absolute --add path (non-physical form) committed" "$(git show --name-only --format= HEAD)" "abs.txt"

mkdir -p sub && echo s > sub/s.txt && echo top > top.txt && git add top.txt && git commit -qm top
echo edit >> top.txt
(cd sub && bash "$script" --commit-msg "feat: x" --pr-title t --pr-body b --add s.txt >/dev/null 2>"$tmp/err")
eq "run from a subdirectory: relative --add and edits outside it staged" "$(git show --name-only --format= HEAD | sort | paste -sd, -)" "sub/s.txt,top.txt"

echo l > .bf/sessions/log.md
echo e >> top.txt
finalize --add .bf/sessions/log.md
eq "--add under .bf/ skipped" "$(git show --name-only --format= HEAD)" "top.txt"
eq "--add under .bf/ noted" "$(grep -c 'skipping --add .bf/sessions/log.md' "$tmp/err")" 1

echo ig.txt > .gitignore && git add .gitignore && git commit -qm ignore
echo i > ig.txt && echo e >> top.txt
before=$(head_sha)
rc=0; finalize --add ig.txt || rc=$?
eq "ignored --add path -> exit 1" "$rc" 1
eq "ignored --add path -> nothing staged" "$(git diff --cached --name-only)" ""
rc=0; finalize --add missing.txt || rc=$?
eq "missing --add path -> exit 1, nothing staged" "$rc $(git diff --cached --name-only)" "1 "
eq "refused runs made no commit" "$(head_sha)" "$before"
finalize
git rm -q --cached .gitignore && rm .gitignore ig.txt && git commit -qm unignore

echo old > old-stray.md
printf 'old-stray.md\0' > "$tmp/baseline"
mkdir -p gen && echo g > gen/snap.txt
rc=0; finalize --baseline "$tmp/baseline" || rc=$?
eq "baseline: stray from session start -> exit 3" "$rc" 3
eq "baseline: only the old stray listed" "$(grep -c '^  ' "$tmp/err") $(grep -c '^  old-stray.md$' "$tmp/err")" "1 1"
finalize --baseline "$tmp/baseline" --leave-untracked
eq "baseline: file made during the session staged without --add" "$(git show --name-only --format= HEAD)" "gen/snap.txt"
eq "baseline: old stray left untracked" "$(git ls-files --others --exclude-standard -- old-stray.md)" "old-stray.md"
echo n2 > n2.txt
rc=0; finalize --baseline "$tmp/no-such-file" || rc=$?
eq "missing baseline file -> strict mode, exit 3" "$rc" 3
rm old-stray.md n2.txt

: > "$tmp/empty-baseline"
git worktree add -q .worktrees/w
git init -q inner && (cd inner && git commit -q --allow-empty -m i)
echo fresh > fresh.txt
rc=0; finalize --baseline "$tmp/empty-baseline" || rc=$?
eq "nested repos -> no exit 3" "$rc" 0
eq "nested repos skipped, normal new file staged" "$(git show --name-only --format= HEAD)" "fresh.txt"
eq "nested repos -> no gitlink in the index" "$(git ls-files -s | grep -c '^160000' || true)" 0
eq "nested repos -> both noted" "$(grep -c 'nested git repo' "$tmp/err")" 2
git worktree remove .worktrees/w && rm -rf .worktrees inner

before=$(head_sha)
echo r2 > .bf/reviews/r2.md
mkdir -p .bf/audit && echo a > .bf/audit/a.md
finalize
eq "only .bf files -> no new commit" "$(head_sha)" "$before"

finalize
eq "clean tree -> no new commit" "$(head_sha)" "$before"

mkdir -p .bf/conventions && echo c > .bf/conventions/style.md
finalize
eq "only a .bf/conventions change -> committed alone" "$(git show --name-only --format= HEAD)" ".bf/conventions/style.md"

echo m >> top.txt
before=$(head_sha) before_remote=$(remote_sha)
pr_head=$(head_sha)
rc=0; GH_PR_STATE=MERGED GH_PR_HEAD=$pr_head finalize || rc=$?
eq "merged PR -> exit 4" "$rc" 4
eq "merged PR -> state named" "$(grep -c 'PR for this branch is MERGED' "$tmp/err")" 1
eq "merged PR -> no commit, nothing staged" "$(head_sha) $(git diff --cached --name-only)" "$before "
eq "merged PR -> remote unchanged" "$(remote_sha)" "$before_remote"
eq "merged PR -> recovery moves only the new commits onto the base" "$(grep -c "rebase --autostash --onto origin/main $pr_head" "$tmp/err")" 1
rc=0; GH_PR_STATE=CLOSED GH_PR_HEAD=$pr_head finalize || rc=$?
eq "closed PR -> exit 4" "$rc" 4
eq "closed PR -> recovery branches from HEAD" "$(grep -c 'new branch from HEAD' "$tmp/err") $(grep -c 'rebase' "$tmp/err" || true)" "1 0"
echo ru >> top.txt
before_remote=$(remote_sha)
rc=0; GH_PR_STATE=MERGED finalize || rc=$?
eq "merged PR from a reused branch name (head not in history) -> proceeds" "$rc" 0
eq "reused branch name -> committed and pushed" "$(git show --name-only --format= HEAD) $(remote_sha)" "top.txt $(head_sha)"
echo ru2 >> top.txt
: > "$tmp/gh.log"
GH_LOG="$tmp/gh.log" GH_PR_STATE=CLOSED finalize
eq "closed PR from a reused branch name -> new PR created" "$(grep -c '^pr create' "$tmp/gh.log" || true)" 1
echo op >> top.txt
url=$(GH_PR_STATE=OPEN bash "$script" --commit-msg "feat: x" --pr-title t --pr-body b 2>"$tmp/err")
eq "open PR -> committed and pushed" "$(git show --name-only --format= HEAD) $(remote_sha)" "top.txt $(head_sha)"
eq "open PR -> existing PR url" "$(printf "%s\n" "$url" | tail -n1)" "https://example.test/pr/9"

echo co >> top.txt
: > "$tmp/gh.log"
before=$(head_sha) before_remote=$(remote_sha)
rc=0; GH_LOG="$tmp/gh.log" GH_PR_STATE=MERGED bash "$script" --commit-only --commit-msg "feat: local" >"$tmp/out" 2>"$tmp/err" || rc=$?
eq "commit-only -> exit 0" "$rc" 0
eq "commit-only -> local commit made" "$(git log -1 --format=%s) $(git show --name-only --format= HEAD)" "feat: local top.txt"
eq "commit-only -> HEAD moved" "$([ "$(head_sha)" != "$before" ] && echo moved)" moved
eq "commit-only -> remote unchanged" "$(remote_sha)" "$before_remote"
eq "commit-only -> no gh call, no PR url" "$([ -s "$tmp/gh.log" ] && echo called || echo none) $(grep -c example.test "$tmp/out" || true)" "none 0"

echo gf >> top.txt
before=$(head_sha) before_remote=$(remote_sha)
rc=0; GH_FAIL=1 finalize || rc=$?
eq "failed PR lookup -> exit 5" "$rc" 5
eq "failed PR lookup -> no commit, nothing staged" "$(head_sha) $(git diff --cached --name-only)" "$before "
eq "failed PR lookup -> remote unchanged" "$(remote_sha)" "$before_remote"

rc=0; GH_FAIL_CREATE=1 finalize || rc=$?
eq "failed PR create after push -> exit 6, not 4" "$rc" 6
eq "failed PR create after push -> remote moved" "$(remote_sha)" "$(head_sha)"

echo fe >> top.txt
rc=0; GH_PR_STATE=OPEN GH_FAIL_EDIT=1 finalize || rc=$?
eq "failed PR edit after push -> exit 6" "$rc" 6

echo fl >> top.txt
: > "$tmp/lookups"
rc=0; GH_LOOKUPS="$tmp/lookups" GH_FAIL_LOOKUP_AFTER=1 finalize || rc=$?
eq "failed PR lookup after push -> exit 6" "$rc" 6
eq "failed PR lookup after push -> remote moved" "$(remote_sha)" "$(head_sha)"

echo mg >> top.txt
: > "$tmp/lookups"
rc=0; GH_LOOKUPS="$tmp/lookups" GH_PR_HEAD=$(head_sha) GH_PR_STATE_AFTER=MERGED finalize || rc=$?
eq "PR merged during the push -> exit 6" "$rc" 6
eq "PR merged during the push -> state named" "$(grep -c 'became MERGED' "$tmp/err")" 1

echo race >> top.txt
: > "$tmp/lookups"; : > "$tmp/gh.log"
GH_LOG="$tmp/gh.log" GH_LOOKUPS="$tmp/lookups" GH_PR_STATE_AFTER=OPEN finalize
eq "PR opened during the push -> edited, not created" "$(grep -c '^pr create' "$tmp/gh.log" || true) $(grep -c '^pr edit' "$tmp/gh.log" || true)" "0 1"

echo mc >> top.txt
git checkout -q -b old-pr
echo old > old.txt && git add old.txt && git commit -qm old
old_head=$(head_sha)
git checkout -q main
git merge -q --no-ff old-pr -m "Merge old-pr"
rc=0; GH_PR_STATE=MERGED GH_PR_HEAD=$old_head finalize || rc=$?
eq "reused name, old PR merged with a merge commit (head in history) -> exit 4, the documented limit" "$rc" 4

[ "$fails" -eq 0 ]
