---
name: do-todo
description: Pick the next unchecked item from the todo file and implement it following the plan.
disable-model-invocation: true
model: sonnet
---

Run the helper script to load state and artifact paths:

```
bash ~/.claude/skills/bfeature-full/scripts/state-ops.sh
```

This gives you `slug`, `build_timestamp`, and `paths.*` — use `paths.todo` and `paths.plan` directly.

Before starting the loop, read these once:
- `conventions/dev.md` — code style and quality rules
- `conventions/testing.md` — test requirements
- `conventions/git.md` — commit message format

Repeat the following loop until no unchecked items remain — do not wait for user approval between iterations:

**Each iteration:**
1. Open the file at `paths.todo` and pick the **first unchecked item** (one item only).
2. Read the relevant section in `paths.plan` for implementation details.
3. Carefully plan your approach before touching any code — think through edge cases, dependencies, and impact on existing code.
4. Implement the item — write robust, readable code, add tests, verify tests pass.
5. Mark the item as checked (`- [x]`) in the todo file immediately after completing it.
6. Commit your changes following `conventions/git.md`. Do **not** stage anything in `.claude/.bfeature-temp/`.
7. Go back to step 1.
