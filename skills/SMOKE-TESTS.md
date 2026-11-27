# Smoke tests

Maintainer reference, not a skill. Run the matching smoke script after changing a script it covers;
each prints one PASS/FAIL line per case and exits non-zero on any failure. Run them with macOS
`/bin/bash` (3.2) first on PATH as well, since that is what many users have. After a change to a jq
filter, also run the smoke with a jq 1.6 binary first on PATH. jq 1.6 rejects syntax that 1.7 accepts
(`{a: x + y}` without parentheses, keywords such as `label` as shorthand keys), and its `-e` exits 0
on empty input.

| Smoke script | Covers |
|---|---|
| `skills/feature/scripts/added-todos-smoke.sh` | `added-todos.sh` |
| `skills/scan-conventions/scripts/resolve-conventions-smoke.sh` | `resolve-conventions.sh`, `convention-tiers.sh`, `discover-conventions.sh` |
| `skills/coherence/scripts/scope-smoke.sh` | `scope.sh` |
| `skills/scan-conventions/scripts/host-rules-smoke.sh` | `host-rules.sh` |
| `skills/feature/scripts/finalize-git-smoke.sh` | `finalize-git.sh` |
| `skills/feature/scripts/check-report-status-smoke.sh` | `check-report-status.sh` (one block, several blocks, the `OVERALL` escalation) |
| `skills/feature/scripts/changed-packages-smoke.sh` | `changed-packages.sh` `changed_files` (committed, uncommitted and untracked files, `.bf/` and nested repos left out, the session baseline read from `state-ops.sh --init`) |
| `skills/feature/scripts/session-untracked-smoke.sh` | `session-untracked.sh` (baseline entries and directory entries, `.bf/` and nested repos left out, non-ASCII names, missing baseline) |
| `skills/feature/scripts/rename-only-smoke.sh` | `rename-only.sh` (pure rename, rename with edits, path-string-only edits, adds) |
| `skills/feature/scripts/write-block-smoke.sh` | `write-block.sh` |
| `skills/feature/scripts/state-ops-smoke.sh` | `state-ops.sh` (`parallel_audit`, `auto_fix_style`, `skip_plan_gates`, `commit_only`, `pending_fixes`, `fixing`, `--archive` with a corrupt state and a same-hour name collision) |
| `skills/feature/scripts/init-probe-smoke.sh` | `init-probe.sh` (`state_matches` for a leftover build state) |
| `skills/review/scripts/merge-gate-reports-smoke.sh` | `merge-gate-reports.sh` (renumbering, severity mapping, `UNKNOWN`, STATUS escalation, a measured-gate group under Advisory Issues) |
| `skills/review/scripts/pr-review-payload-smoke.sh` | `pr-review-payload.sh` (inline vs body placement against the diff) |
| `skills/self-audit/scripts/audit-static-smoke.sh` | `audit-static.sh` (kit-template reference check) |
| `skills/onboard-project/scripts/onboard-probe-smoke.sh` | `onboard-probe.sh` (`init`, `verify`, `promote` and `brief`) |
| `skills/visualize/scripts/visualize-smoke.sh` | `viz-paths.sh`, `resolve-spec.sh`, `install-likec4.sh`, `classify-output.sh`, `c4-facts.sh`, `build.sh` (the install and real-build cases need the network and print SKIP offline) |
| `skills/bug-hunt/scripts/bug-hunt-smoke.sh` | `hunt-init.sh` (including the `--pr --worktree` paths against a stub `gh` and a local bare origin), `profile.sh`, `findings.sh` |
| `skills/autopilot/hooks/autopilot-hooks-smoke.sh` | `stop.sh`, `user-prompt-cleanup.sh`, `session-start-cleanup.sh`, the helpers in `lib.sh` (sub-agents, teammates and background work, stop words, agent and scheduled turns, the lead session and its process, the second-session warning) |
| `skills/essence/scripts/essence-smoke.sh` | `essence-init.sh`, `ledger-check.sh` |
| `skills/cross-agent/scripts/cross-agent-smoke.sh` | `cross-agent-init.sh`, `cross-agent-assemble.sh`, `runners/codex.sh` (arguments kept verbatim from a file, the skill-name check and `<skill>/<sub-skill>` names, the `--read-only` sandbox passed to codex, the reference closure and the split reading list, `@sh`-quoted run commands, bad bundles refused, parallel inits, every error code named in SKILL.md, a missing `codex`) |
| `skills/pr-comments/scripts/pr-comments-smoke.sh` | `fetch-pr-comments.sh`, `wait-for-review.sh` (argument parsing, `--all`, push time, `--head` and `--bot`, against a stub `gh`) |
| `hooks/remote-state-hook-smoke.sh` | `hooks/remote-state-pre-bash.sh` (which commands get the reminder, `BF_REMOTE_HOOK=off`, input that is not JSON, the `hooks.json` registration under PreToolUse Bash) |
| `hooks/deps-index-smoke.sh` | `hooks/deps-index.sh` (each manifest parser, incremental rebuild, `read` freshness and path prefix filter, concurrent builds and the dead work dir sweep, `BF_DEPS_HOOK=off`, the background start, the `hooks.json` registration, and the manifest list agreeing with `conventions/reuse.md`) |
| `hooks/skill-suggest-smoke.sh` | `hooks/skill-suggest-stop.sh` (the local guards, the transcript scan with its fixture, the catalog and its reason and trigger phrase rules, the TypeSafe exit codes and the hook faults that stay silent, the keyword fallback, the tip text, the per-session dedupe, the local log, the time bound, the banner prefix of every candidate skill, and the `hooks.json` registration). The cases sit in `main`, and each case runs in a fresh HOME with a TypeSafe stub, so a run never reaches the real log or the live API |
| `skills/setup/scripts/setup-smoke.sh` | `setup.sh` (`status`, `check`, `plan` and `install`, against stub `brew`, `apt-get`, `sudo`, `git`, `npm` and python, in a fake HOME and PATH: the registry `requires` order, the readiness rule, the `no_brew` stop, `--only`, the python placeholder in one batch with crapper, skipped dependents, a second run that does nothing) |
| `skills/feature/scripts/measured-gate-smoke.sh` | `measured-gate.sh` (the two skip lines, the coverage flag, one finding group per tool, the mutator exit codes, a tool crash, the `.metrics` cleanup, a path with a space, a partial install, the time limit, and the 540 s and `timeout: 600000` pair with `complexity-gate/SKILL.md`). Its fixtures come from the tools' own report formatters |
| `skills/refactor-scout/scripts/scout-smoke.sh` | `scout.sh` and the shared `measured_tools.py` (the applicability check per tool for Scala, JavaScript and a mixed scope, a coverage flag on every crapper call, ranking by churn with a stable section, dryer pairs merged into one cluster, `show` and `check` PASS and FAIL for crapper and dryer, code moved into a new file, `--mutate`, `check` on a mutator candidate, the `UNKNOWN` verdict, each error code, the shallow-clone note, an untracked or changed file ranked active, unit cases for the pure functions in `scout-unit.py`, a scope path with a space, parentheses, a quote and a leading `#`, the time limit, and the 480 s and `timeout: 600000` pair with `SKILL.md`) |
| `evals/regress-smoke.sh` | `evals/regress.sh` (all modes, against a stub `claude`) and `.githooks/pre-push` |
| `hooks/prose-hooks-smoke.sh` | the `hooks/prose-*.sh` hooks and `prose-lib.sh` (skip list, record directory guards, `prose_commit_values` tokenizer) |
| `skills/plain/scripts/prose-lint.sh --selftest` | `prose-lint.sh` (hard markers, soft markers, rules validation, modes, `--digest`, `--classify`) |
| `skills/feature/scripts/report-template-smoke.sh` | `## <Name> Report` / `## <Name> Review` examples in every SKILL.md: sub-sections stay `###` or deeper, so `read-block.sh` reads the whole block |
