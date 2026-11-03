#!/usr/bin/env bash
# Append the complexity and consistency gate findings to a review report, and set its STATUS.
#
# Usage: merge-gate-reports.sh <report> <gate-file> [--complexity] [--consistency] [--review-failed]
#   <report>         the review report to append to
#   <gate-file>      the file holding the "## Complexity Report" and "## Consistency Report" blocks
#   --complexity     merge the complexity gate (omit when the focus did not enable it)
#   --consistency    merge the consistency gate (omit when the focus did not enable it)
#   --review-failed  the review Agent failed; STATUS becomes CONCERN whatever the gates found
#
# Each merged section gets its findings renumbered X1.., Y1.. in order. A BLOCK finding becomes
# [must-fix], an ADVISORY finding [should-consider]. A missing gate block gives
# "STATUS: UNKNOWN (...)". STATUS in the report becomes CONCERN when any C*, X* or Y* finding
# exists, a merged gate STATUS is not PASS, or --review-failed is set; its focus suffix stays.
# A non-PASS gate whose findings the parser cannot read is copied verbatim under a marker line, so
# no finding is dropped.
#
# Format dependency: the parser reads the Report Format of feature/complexity-gate/SKILL.md and
# feature/consistency-gate/SKILL.md: the "###" severity headers, the "####" group lines, the
# "- `loc`, **Lens**: text" finding line and the **Fix:**/**Suggestion:** labels. Change those
# templates and this parser together, then run merge-gate-reports-smoke.sh.
# Output: one line, "STATUS: <PASS|CONCERN>" as written to the report.
set -euo pipefail

[ $# -ge 2 ] || { echo "Usage: merge-gate-reports.sh <report> <gate-file> [--complexity] [--consistency] [--review-failed]" >&2; exit 1; }
report=$1; gate_file=$2; shift 2
complexity=0; consistency=0; failed=0; escalate=0
for a in "$@"; do
  case "$a" in
    --complexity) complexity=1 ;;
    --consistency) consistency=1 ;;
    --review-failed) failed=1 ;;
    *) echo "Unknown argument: $a" >&2; exit 1 ;;
  esac
done
[ -f "$report" ] || { echo "Report not found: $report" >&2; exit 1; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
feature_scripts="$here/../../feature/scripts"

section() { # <gate> <block header> <Section title> <id prefix>
  local gate=$1 header=$2 title=$3 prefix=$4 status body
  status=$(bash "$feature_scripts/check-report-status.sh" "$gate_file" --block "$header")
  if [ "$status" = NOT_FOUND ]; then
    printf '\n## %s\nSTATUS: UNKNOWN (%s gate failed — see conversation)\n' "$title" "$gate" >>"$report"
    return 0
  fi
  body=$(bash "$feature_scripts/read-block.sh" "$gate_file" --block "$header")
  printf '\n## %s\nSTATUS: %s\n' "$title" "$status" >>"$report"
  [ "$status" = PASS ] && return 0
  escalate=1
  printf '%s\n' "$body" | python3 -c '
import re, sys
prefix = sys.argv[1]
severity, group, n, out = None, None, 0, []
sys.stdin_lines = sys.stdin.read().split("\n")
for line in sys.stdin_lines:
    m = re.match(r"^###\s+(.*)", line)
    if m:
        severity = "[must-fix]" if re.search(r"block", m.group(1), re.I) else "[should-consider]" if re.search(r"advisory", m.group(1), re.I) else severity
        continue
    m = re.match(r"^####\s+(.*)", line)
    if m:
        group = m.group(1).strip()
        out.append("\n### " + group)
        continue
    m = re.match(r"^- (`[^`]+`)(?:, \*\*([^*]+)\*\*)?:\s*(.*)", line)
    if m and severity:
        loc, lens, text = m.groups()
        if lens and lens.strip() != group:
            group = lens.strip()
            out.append("\n### " + group)
        text = re.sub(r"\*\*(?:Fix|Suggestion):\*\*", "Suggested:", text)
        n += 1
        out.append("- **%s%d** %s %s: %s" % (prefix, n, severity, loc, text))
    elif out and line.strip() and not line.startswith("#"):
        out.append(line)
if n == 0:
    out = ["(unparsed gate findings, copied as written)"] + [l for l in sys.stdin_lines if l.strip()]
print("\n".join(out).lstrip("\n"))
' "$prefix" >>"$report"
}

[ "$complexity" -eq 1 ] && section complexity "## Complexity Report" Complexity X
[ "$consistency" -eq 1 ] && section consistency "## Consistency Report" Consistency Y

if [ "$failed" -eq 1 ] || [ "$escalate" -eq 1 ] || grep -qE '^- \*\*[CXY][0-9]+\*\*' "$report"; then
  python3 - "$report" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
for i, l in enumerate(lines):
    if l.startswith("STATUS:"):
        lines[i] = re.sub(r"^STATUS:\s*PASS", "STATUS: CONCERN", l)
        break
open(p, "w").write("\n".join(lines))
PY
fi
grep -m1 '^STATUS:' "$report"
