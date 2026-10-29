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
files=$(find "$root" -name SKILL.md -print | LC_ALL=C sort)
# Files are looped in the main shell (no pipe/process substitution) so an awk failure is seen and counted.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rc=0
  out=$(awk -v f="$f" '
    { line = $0; sub(/^[ \t]+/, "", line)
      # Inside a fence, markdown strips up to the opener'"'"'s indent from content lines; a column-0 fence strips nothing.
      body = $0; n = 0
      while (n < ind && substr(body, 1, 1) == " ") { body = substr(body, 2); n++ } }
    # A fence closes only on a run of backticks at least as long as the one that opened it,
    # so a ```` example that quotes ``` blocks stays one example. Indented fences count too.
    match(line, /^`{3,}/) {
      ticks = RLENGTH
      if (!open) { open = ticks; report = 0; bad = ""; ind = length($0) - length(line); next }
      if (ticks >= open && line ~ /^`+[ \t]*$/) {
        if (report) print (bad == "" ? "PASS " : "FAIL ") f ":" start " " head (bad == "" ? "" : " — H2 inside the block at line" bad)
        open = 0; report = 0; next
      }
    }
    # The report header may follow preamble lines; only H2s after it are a problem.
    open && !report && body ~ /^## .*(Report|Review)[ \t]*$/ { report = 1; start = NR; head = body; next }
    open && report && body ~ /^## / { bad = bad " " NR }
    END { if (open && report) print "FAIL " f ":" start " " head " — report fence never closed" }
  ' "$f" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    found=1; fail=1
    echo "FAIL $f — awk exited $rc: $(printf '%s' "$out" | tr '\n' ' ')"
    continue
  fi
  [ -n "$out" ] || continue
  while IFS= read -r line; do
    found=1
    case $line in FAIL*) fail=1 ;; esac
    echo "$line"
  done <<EOF
$out
EOF
done <<EOF
$files
EOF

[ "$found" = 1 ] || { echo "FAIL no report templates found under $root"; exit 1; }
exit $fail
