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
case "$1 $2" in
  "pr create") echo "https://example.test/pr/1" ;;
  "pr view") exit 1 ;;
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

finalize() { bash "$script" --commit-msg "feat: x" --pr-title t --pr-body b >/dev/null 2>&1; }
head_sha() { git rev-parse HEAD; }

mkdir -p src .bf/reviews .bf/sessions
echo n > src/new.txt
echo r > .bf/reviews/r.md
echo s > .bf/sessions/s.md
before=$(head_sha)
finalize
eq "untracked source file committed" "$(git show --name-only --format= HEAD)" "src/new.txt"
eq "a new commit was made" "$([ "$(head_sha)" != "$before" ] && echo yes)" yes

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

[ "$fails" -eq 0 ]
