#!/usr/bin/env bash
# Measure a scope with crapper, dryer and mutator, rank refactoring candidates, and re-check one later.
#
# Usage:
#   scout.sh scan [--only crapper|dryer] [--mutate] < <paths file>
#   scout.sh show <id|run/id>
#   scout.sh check <id|run/id>
#   The paths file holds the scope, one path per line, relative to the current directory. An empty file
#   means the whole repository. show and check read no stdin.
#
# Output: one JSON object on stdout, exit 0. Errors: {"error":"<code>","detail":"..."}, exit 1.
#   scan  -> {"applicable": false, "reason": ...} when no selected tool can measure the scope, else
#            {"applicable": true, "run", "report", "tools", "groups", "notes"}. The report and
#            candidates.json go to <root>/.bf/refactor-scout/<run>/. A file that is untracked or changed
#            against HEAD counts as active, never stable.
#   show  -> {"run", "head", "candidate"}
#   check -> {"run", "id", "verdict": "PASS"|"FAIL"|"UNKNOWN", "done_when", "before", "after", "details",
#            "touched", "notes"}
#
# Time limit: tools stop at SCOUT_BUDGET_S (480) and churn stops 45 s (CHURN_S) after the tools, file churn and
# function churn together. A tool past its limit also gets 5 s of TERM grace. SKILL.md passes timeout 600000 on
# every scan and check call. scout-smoke.sh checks that the three add up to less than that value.
#
# Side effect: the tools write .metrics, target and coverage at the repository root. Each run removes the
# ones it created, as measured-gate.sh does.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v python3 >/dev/null 2>&1 || { echo '{"error":"no_python3","detail":"python3 is not installed. Run /bf:setup."}'; exit 1; }

PYTHONDONTWRITEBYTECODE=1 MEASURED_TOOLS_DIR="$here/../../feature/scripts" SETUP_SH="$here/../../setup/scripts/setup.sh" \
  exec python3 "$here/scout.py" "$@"
