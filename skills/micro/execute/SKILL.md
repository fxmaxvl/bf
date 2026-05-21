---
name: micro-execute
description: Implement a focused refactoring from the instruction stored in state. No plan file — derives implementation directly from paths.qa.
disable-model-invocation: true
model: sonnet
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper script to load state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"
```

This gives you `slug`, `build_timestamp`, `artifacts_dir`, and `paths.*`.

Read the task instruction from `paths.qa`.

Before writing any code, read:
- `${CLAUDE_PLUGIN_ROOT}/conventions/dev.md`
- `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md`
- `${CLAUDE_PLUGIN_ROOT}/conventions/git.md`

Implement the refactoring:

1. Locate the relevant code — find the file(s) and method(s) mentioned in the instruction.
2. Plan your approach internally — think through edge cases, caller impact, and test changes needed. Do not output this plan.
3. Make the changes. Keep scope tight: only modify what the instruction describes.
4. Update or add tests as needed.
5. Commit following `conventions/git.md`. Use `refactor:` prefix. Do **not** stage anything in `.bf/sessions/`.
