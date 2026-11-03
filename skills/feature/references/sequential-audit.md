# Sequential audit (`parallel_audit: false`)

This is the opt-out branch of Phase 4.75. The orchestrator in `feature/SKILL.md` has already printed the banner, read the shared rules and branched on `parallel_audit`.

**Record start timestamp** before the first scan cycle — store it in state, where it survives across orchestrator turns:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" audit_started_at=$(date -u +%s)
```

Run up to 3 scan → fix cycles (complexity & consistency):

1. Empty both report blocks first, so a block from review-design or an earlier cycle cannot pass for this cycle's report: `: | bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/write-block.sh" <paths.temp> --block "<header>"` for `## Complexity Report` and `## Consistency Report`. Then run both gates in parallel per the **Parallel Fan-Out** convention in `plugin-main.md` — named so they show on the fleet board (phase is `verify` — both skills auto-detect scan mode):
   - `complexity-gate`: dispatch `feature/complexity-gate/SKILL.md` as an Agent (model: opus)
   - `consistency-gate`: dispatch `feature/consistency-gate/SKILL.md` as an Agent (model: opus)
   Start the silent-agent watch from **Parallel Fan-Out** after the spawn.
2. Check both reports:
   `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "<paths.temp>" --block "## Complexity Report" --block "## Consistency Report"`
   Act on its `OVERALL:` line (`PASS`, `ADVISORY`, `BLOCK` or `NOT_FOUND`); on `NOT_FOUND`, re-run the gate its per-block line names once, then check again. If the report is still `NOT_FOUND` after the re-run, do not enter the `BLOCK` branch, which has nothing to fix: tell the user which gate produced no report and ask one question, re-run that gate again or proceed without its report. On proceed, record the missing gate in the session log.
3. If overall STATUS is `PASS` or `ADVISORY`: show findings if any, proceed to step 5
4. If overall STATUS is `BLOCK`:
   - Show the blocked issues from both reports to the user
   - Ask: "Should I fix these issues?"
   - If yes: record **Pending fixes**, then spawn a fix agent (model: sonnet) with this prompt: "Read the `## Complexity Report` and `## Consistency Report` blocks with `bash \"${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/read-block.sh\" <paths.temp> --block \"## <name>\"` — one call per block. For each issue under Blocked Issues in either report, apply the prescribed fix. Do not modify any file outside `changed_files`. Follow the `dev` convention (resolved via the lookup in `plugin-main.md`). Apply the rules in `<prose path>` to code comments and to all prose you return."
     Then go back to step 1
   - If no (user accepts as-is): proceed to step 5
   - If this was already the 3rd cycle: tell the user "Max fix cycles reached. Review the blocked issues manually." and stop
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=review-impl phase_status=in_progress
   ```
6. Proceed immediately to Phase 5 (no approval gate)
