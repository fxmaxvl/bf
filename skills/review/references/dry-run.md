# Dry-run preview

When `dry_run=true`, skip every Agent spawn and exit before Phase 1 work begins. Print a structured preview so the user can see exactly what would run, then stop. No report is written, no `build-state.json` is created, no symlink is updated.

Steps:

1. Resolve conventions exactly as Phase 1 does, in the current repo (a dry-run never clones) — one `resolve-conventions.sh` call for `code-review`, `dev`, `testing`, `architecture`, `prose`, plus one `host-rules.sh` call — but do **not** read the file bodies. Capture only the resolved absolute paths.
2. Print this block (plain text, not in a code fence):

   ```
   bf:review dry-run
   Scope: <scope description: "current branch diff vs origin/HEAD" if the scope text is empty, else the scope text left after flags and focus are stripped>
   Focus: <focus_label>
   Report would be written to: <report_path>
   Resolved conventions:
     - code-review: <resolved path or "MISSING">
     - dev:         <resolved path or "MISSING">
     - testing:     <resolved path or "MISSING">
     - architecture: <resolved path or "MISSING">
     - prose:       <resolved path or "MISSING">
   Host repository rules: <one path per line from host_rules, or "none">
   Agents that would be spawned (skipped in dry-run):
     - review Agent        (model: opus), Phase 1 parallel batch
     - complexity-gate Agent (model: opus), Phase 1 parallel batch
     - consistency-gate Agent (model: opus), Phase 1 parallel batch
   All <N> dispatched in a single message. Phase 2 aggregates the results.
   Interactive phases that would follow (skipped in dry-run):
     - Post to PR (PR scope only)
     - Phase 3 fix selection
     - Phase 4 fix apply + re-review
   ```

   List only the agents whose `run_review` / `run_complexity` / `run_consistency` is true. Do not name the others, not even as skipped. When only one agent would run, replace the "All <N> dispatched" line with "Dispatched alone. Phase 2 aggregates the results."

3. Exit. Do not proceed to Phase 1.
