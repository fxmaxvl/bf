# Smoke tests

Maintainer reference, not a skill. Run the matching smoke script after changing a script it covers;
each prints one PASS/FAIL line per case and exits non-zero on any failure. Run them with macOS
`/bin/bash` (3.2) first on PATH as well, since that is what many users have.

| Smoke script | Covers |
|---|---|
| `skills/feature/scripts/added-todos-smoke.sh` | `added-todos.sh` |
| `skills/scan-conventions/scripts/resolve-conventions-smoke.sh` | `resolve-conventions.sh`, `convention-tiers.sh`, `discover-conventions.sh` |
| `skills/coherence/scripts/scope-smoke.sh` | `scope.sh` |
| `skills/scan-conventions/scripts/host-rules-smoke.sh` | `host-rules.sh` |
| `skills/feature/scripts/finalize-git-smoke.sh` | `finalize-git.sh` |
| `skills/feature/scripts/check-report-status-smoke.sh` | `check-report-status.sh` (one block, several blocks, the `OVERALL` escalation) |
| `skills/feature/scripts/rename-only-smoke.sh` | `rename-only.sh` (pure rename, rename with edits, path-string-only edits, adds) |
| `skills/feature/scripts/write-block-smoke.sh` | `write-block.sh` |
| `skills/feature/scripts/state-ops-smoke.sh` | `state-ops.sh` (`parallel_audit`, `auto_fix_style`, `skip_plan_gates`, `pending_fixes`, `--archive` with a corrupt state and a same-hour name collision) |
| `skills/feature/scripts/init-probe-smoke.sh` | `init-probe.sh` (`state_matches` for a leftover build state) |
| `skills/review/scripts/merge-gate-reports-smoke.sh` | `merge-gate-reports.sh` (renumbering, severity mapping, `UNKNOWN`, STATUS escalation) |
| `skills/review/scripts/pr-review-payload-smoke.sh` | `pr-review-payload.sh` (inline vs body placement against the diff) |
| `skills/self-audit/scripts/audit-static-smoke.sh` | `audit-static.sh` (kit-template reference check) |
| `skills/onboard-project/scripts/onboard-probe-smoke.sh` | `onboard-probe.sh` (`init`, `verify`, `promote` and `brief`) |
| `skills/visualize/scripts/visualize-smoke.sh` | `viz-paths.sh`, `resolve-spec.sh`, `install-likec4.sh`, `classify-output.sh`, `c4-facts.sh`, `build.sh` (the install and real-build cases need the network and print SKIP offline) |
| `skills/bug-hunt/scripts/bug-hunt-smoke.sh` | `hunt-init.sh`, `findings.sh` |
| `skills/autopilot/hooks/autopilot-hooks-smoke.sh` | `stop.sh`, `user-prompt-cleanup.sh`, `session-start-cleanup.sh`, the stop-prompt matcher in `lib.sh` (sub-agents, teammates and background work, stop prompts against status checks) |
| `skills/essence/scripts/essence-smoke.sh` | `essence-init.sh`, `ledger-check.sh` |
| `skills/pr-comments/scripts/pr-comments-smoke.sh` | `fetch-pr-comments.sh`, `wait-for-review.sh` (argument parsing, `--all`, push time, `--head` and `--bot`, against a stub `gh`) |
| `skills/feature/scripts/report-template-smoke.sh` | `## <Name> Report` / `## <Name> Review` examples in every SKILL.md: sub-sections stay `###` or deeper, so `read-block.sh` reads the whole block |
