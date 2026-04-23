---
name: review-design-fix
description: Apply fixes to a feature spec based on concerns from the design review report.
disable-model-invocation: true
model: sonnet
---

Run the helper script to load state and artifact paths:

```
bash "$(find ~/.claude -name state-ops.sh -path '*/full/scripts/*' 2>/dev/null | head -1)"
```

This gives you `paths.design_report` and `paths.spec`.

Read the file at `paths.design_report` for the list of concerns.
Read the file at `paths.spec` for the current spec.

Update the file at `paths.spec` in place to address every concern listed in the report.

Do **not** re-run the review and do **not** ask the user questions — the orchestrator handles both.
