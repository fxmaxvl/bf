---
name: do-todo
description: Pick the next unchecked item from the todo file and implement it following the plan.
disable-model-invocation: true
model: sonnet
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper script to load state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"
```

This gives you `slug`, `build_timestamp`, and `paths.*` — use `paths.todo` and `paths.plan` directly.

Before starting the loop, read these once:
- `${CLAUDE_PLUGIN_ROOT}/conventions/dev.md` — code style and quality rules
- `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md` — test requirements
- `${CLAUDE_PLUGIN_ROOT}/conventions/git.md` — commit message format

Repeat the following loop until no unchecked items remain — do not wait for user approval between iterations:

**Each iteration:**
1. Open the file at `paths.todo` and pick the **first unchecked item** (one item only).
2. Read the relevant section in `paths.plan` for implementation details.
3. Carefully plan your approach before touching any code — think through edge cases, dependencies, and impact on existing code.
4. Implement the item — write robust, readable code, add tests, verify tests pass.
5. Mark the item as checked (`- [x]`) in the todo file immediately after completing it.
6. Commit your changes following `${CLAUDE_PLUGIN_ROOT}/conventions/git.md`. Use `feat:` for new functionality, `fix:` for bug corrections within the feature. Do **not** stage anything in `.claude/.bfeature-temp/`.
7. Go back to step 1.
