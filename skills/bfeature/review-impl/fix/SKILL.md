---
name: review-impl-fix
description: Apply fixes to implementation based on concerns from the implementation review report.
disable-model-invocation: true
model: sonnet
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper script to load state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"
```

This gives you `slug`, `build_timestamp`, `mode`, and `paths.*`.

Read the file at `paths.impl_report` for the list of concerns.

**Mode-aware context:**
- **Full mode** (`mode` = `"full"`): Read `paths.spec` and `paths.plan` for context.
- **Quick mode** (`mode` = `"quick"`): No spec exists. Read `paths.qa` and `paths.plan` for context.

Implement fixes for every concern listed in the report. For each concern:
- If it's a missing feature: implement it
- If it's a convention violation: correct it in place
- If it's a missing test: write the test
- If it's a code style issue: refactor it

After implementing all fixes, commit following the `git` convention (resolved via the lookup in `plugin-main.md`). Use a `fix:` prefix (e.g., `fix: address implementation review concerns`). If `github_issue.enabled` is `true` in state, include the issue number (e.g., `fix(#12): address implementation review concerns`). If `jira.enabled` is `true`, include the ticket key (e.g., `fix(PROJ-123): address implementation review concerns`). Do **not** stage anything in `.bf/sessions/`.

Do **not** re-run the review and do **not** ask the user questions — the orchestrator handles both.
