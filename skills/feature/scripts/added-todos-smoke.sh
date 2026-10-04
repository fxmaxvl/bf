#!/usr/bin/env bash
# Smoke test for added-todos.sh against a throwaway git repo.
#
# Usage: added-todos-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/added-todos.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

fails=0
check() { # <name> <jq-filter-or-condition-result>
  if [ "$2" = ok ]; then echo "PASS $1"; else echo "FAIL $1: $2"; fails=$((fails+1)); fi
}
# eq <name> <actual> <expected>
eq() { if [ "$2" = "$3" ]; then check "$1" ok; else check "$1" "got [$2], want [$3]"; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main repo
cd repo
git config commit.gpgsign false
printf 'l1\nl2\n# TODO: old\nl4\nl5\nl6\n' > a.txt
printf 'x1\nx2\n' > b.txt
git add . && git commit -qm base
git branch base

git checkout -q -b feat
printf 'l1\nl2\n# TODO: old\nl4\nl5\nl6\nl7\n# TODO(me): new one\nl9\nl10\n' > a.txt
printf 'x1\nmastodon here\nsee todos\nrun added-todos.sh\n# todo x\nx7 TODO: in b\n' > b.txt
git add . && git commit -qm feat

out=$(bash "$script" base)
eq "1 added TODOs at HEAD lines, old one excluded" \
  "$(jq -c '[.[]|[.file,.line]]' <<<"$out")" '[["a.txt",8],["b.txt",5],["b.txt",6]]'

eq "2 word boundary" \
  "$(jq -r '[.[]|select(.file=="b.txt")|.text]|join("|")' <<<"$out")" '# todo x|x7 TODO: in b'
eq "2 TODO(me) reported" "$(jq -r '[.[]|select(.file=="a.txt")|.text]|join("|")' <<<"$out")" '# TODO(me): new one'

eq "3 restricted to one file" "$(bash "$script" base b.txt | jq -c '[.[].file]|unique')" '["b.txt"]'

eq "4 context is +-2 lines from HEAD" \
  "$(jq -r '.[]|select(.file=="a.txt")|.context' <<<"$out" | paste -sd'|' -)" 'l6|l7|# TODO(me): new one|l9|l10'

git checkout -q -b clean base
echo extra >> b.txt && git commit -qam clean
eq "5 no TODOs -> []" "$(bash "$script" base)" '[]'

set +e
bad=$(bash "$script" nope-ref); rc=$?
set -e
eq "6 bad base" "$(jq -r .error <<<"$bad"):$rc" 'bad_base:1'

git checkout -q --orphan unrelated
git rm -rfq . && echo z > z.txt && git add z.txt && git commit -qm orphan
git checkout -q feat
set +e
nb=$(bash "$script" unrelated); rc=$?
set -e
eq "7 no merge base -> diff_failed" "$(jq -r .error <<<"$nb"):$rc" 'diff_failed:1'

cfg=$(GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=diff.noprefix GIT_CONFIG_VALUE_0=true \
      GIT_CONFIG_KEY_1=color.diff GIT_CONFIG_VALUE_1=always bash "$script" base)
eq "8 independent of user diff config" "$cfg" "$out"

git checkout -q -b tricky base
printf 'x1\nx2\n++ b/x TODO: sneaky\nplain\n' > b.txt
printf 'l1\nl2\n# TODO: old\nl4\nl5\nl6\n// TODO: real\n' > a.txt
git add . && git commit -qm tricky
eq "9 content line shaped like a header" \
  "$(bash "$script" base | jq -c '[.[]|[.file,.line]]')" '[["a.txt",7],["b.txt",3]]'

[ "$fails" -eq 0 ]
