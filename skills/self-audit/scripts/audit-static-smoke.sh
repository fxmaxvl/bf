#!/usr/bin/env bash
# Smoke test for audit-static.sh's kit-template reference check against a throwaway copy of the repo.
#
# Usage: audit-static-smoke.sh
# Output: one PASS/FAIL line per case; exit 0 when every case passes, 1 otherwise.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/audit-static.sh
src=$(cd "$here/../../.." && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }

copy=$tmp/copy
mkdir "$copy"
cp -R "$src/skills" "$src/conventions" "$src/README.md" "$copy/"
git init -q "$copy"

audit() { TYPESAFE_ASK=/usr/bin/false bash "$script" --root "$copy"; }
kit_findings='[.findings[]|select(.check=="broken-ref" and (.path|startswith("skills/kit/templates/")))|.audit_id]'

eq "untouched copy: no kit-template broken-ref" "$(audit | jq -c "$kit_findings")" '[]'

sub_findings='[.findings[]|select(.check=="broken-subskill-ref" and .path=="skills/zz-probe/SKILL.md")|.audit_id]'
mkdir -p "$copy/skills/zz-probe"
printf 'See `<KIT>/skills/gone/SKILL.md` and `gone-skill/sub/SKILL.md`.\n' > "$copy/skills/zz-probe/SKILL.md"
eq "placeholder-rooted ref exempt, bare missing ref flagged" "$(audit | jq -c "$sub_findings")" \
  '["broken-subskill-ref:skills/zz-probe/SKILL.md:gone-skill/sub/SKILL.md"]'
rm -r "$copy/skills/zz-probe"

tpl=skills/kit/templates/skills/adopt-skill/SKILL.md
sed 's|/context/main.md|/context/mian.md|' "$copy/$tpl" > "$copy/$tpl.new" && mv "$copy/$tpl.new" "$copy/$tpl"
eq "typo'd template ref is reported" "$(audit | jq -c "$kit_findings")" "[\"broken-ref:$tpl:context/mian.md\"]"

rm "$copy/skills/kit/scripts/kit-scaffold.sh"
out=$(audit)
eq "no scaffold: no kit-template finding" "$(jq -c "$kit_findings" <<<"$out")" '[]'
eq "no scaffold: notes say refs were not checked" \
  "$(jq '[.notes[]|select(contains("were not checked"))]|length' <<<"$out")" 1

[ "$fails" -eq 0 ]
