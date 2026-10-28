#!/usr/bin/env bash
# Smoke check for report templates: read-block.sh ends a block at the next `## ` line, so a fenced
# `## <Name> Report` / `## <Name> Review` example whose sub-sections use `##` would hand fix agents
# only the STATUS line. Every sub-section inside such an example must be `###` or deeper.
#
# Usage: report-template-smoke.sh [skills_dir]   # defaults to this plugin's skills/
# Output: one PASS/FAIL line per report example; exit 0 when all pass, 1 otherwise.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "${1:-$dir/../..}" 2>/dev/null && pwd) || { echo "FAIL no such directory: ${1:-}"; exit 1; }

found=0
fail=0
while IFS= read -r line; do
  found=1
  case $line in FAIL*) fail=1 ;; esac
  echo "$line"
done < <(find "$root" -name SKILL.md -print | LC_ALL=C sort | while IFS= read -r f; do
  awk -v f="$f" '
    # A fence closes only on a run of backticks at least as long as the one that opened it,
    # so a ```` example that quotes ``` blocks stays one example.
    match($0, /^`{3,}/) {
      ticks = RLENGTH
      if (!open) { open = ticks; first = 1; report = 0; bad = ""; next }
      if (ticks >= open && $0 ~ /^`+[[:space:]]*$/) {
        if (report) print (bad == "" ? "PASS " : "FAIL ") f ":" start " " head (bad == "" ? "" : " — H2 inside the block at line" bad)
        open = 0; next
      }
    }
    open && first && $0 ~ /[^[:space:]]/ {
      first = 0
      if ($0 ~ /^## .*(Report|Review)[[:space:]]*$/) { report = 1; start = NR; head = $0 }
      next
    }
    open && report && /^## / { bad = bad " " NR }
  ' "$f"
done)

[ "$found" = 1 ] || { echo "FAIL no report templates found under $root"; exit 1; }
exit $fail
