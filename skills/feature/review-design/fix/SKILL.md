---
name: review-design-fix
description: Apply fixes to a feature spec based on concerns from the design review report.
disable-model-invocation: true
model: sonnet
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper script to load state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"
```

This gives you `paths.design_report`, `paths.spec`, and the relevant block headers.

Extract the `## Design Report` block from `paths.design_report` (= `paths.temp`) for the list of concerns (Block Reading Pattern from `plugin-main.md`).
Extract the `## Spec` block from `paths.spec` (= `paths.session_log`) for the current spec.

Update the `## Spec` block in `paths.spec` in place to address every concern — edit only the content between `## Spec` and the next `## ` header (or EOF).

Do **not** re-run the review and do **not** ask the user questions — the orchestrator handles both.
