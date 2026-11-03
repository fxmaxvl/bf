#!/usr/bin/env bash
# Smoke test for rename-only.sh against a throwaway repo.
#
# Usage: rename-only-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

repo=$tmp/repo
mkdir -p "$repo"
cd "$repo"
git init -q -b base . && git config user.email t@t && git config user.name t
printf 'line one\nline two\nline three\nline four\nline five\nline six\n' >old.txt
printf 'import x from "./a/mod"\nconst y = 1\n' >code.js
git add . && git commit -qm base
probe() { bash "$dir/rename-only.sh" --base base; }
reset() { git checkout -q -B work base; }

reset
eq "empty diff -> false" "$(probe)" "skip: false"

reset; git mv old.txt new.txt && git commit -qm mv
eq "pure rename -> true" "$(probe)" "skip: true"

reset; git mv old.txt new.txt && echo extra >>new.txt && git commit -qam mv-edit
eq "rename with an edit -> false" "$(probe)" "skip: false"

reset; sed -i.bak 's#"./a/mod"#"./b/mod"#' code.js && rm code.js.bak && git commit -qam path
eq "path string change only -> true" "$(probe)" "skip: true"

reset; sed -i.bak 's#const y = 1#const y = 2#' code.js && rm code.js.bak && git commit -qam value
eq "code change -> false" "$(probe)" "skip: false"

reset; echo new >added.txt && git add . && git commit -qm add
eq "added file -> false" "$(probe)" "skip: false"

reset; git mv old.txt new.txt && sed -i.bak 's#"./a/mod"#"./b/mod"#' code.js && rm code.js.bak && git commit -qam both
eq "rename plus path string edit -> true" "$(probe)" "skip: true"

reset; printf 'if role == "admin" then\n' >auth.txt && git add . && git commit -qm auth && git branch -f base HEAD
reset; sed -i.bak 's#"admin"#"guest"#' auth.txt && rm auth.txt.bak && git commit -qam role
eq "non-path string change -> false" "$(probe)" "skip: false"

reset; printf "It's fine and don't\n" >prose.md && git add . && git commit -qm prose && git branch -f base HEAD
reset; sed -i.bak 's#fine#bad#' prose.md && rm prose.md.bak && git commit -qam prose-edit
eq "prose edit between apostrophes -> false" "$(probe)" "skip: false"

[ "$fails" -eq 0 ]
