---
name: do-todo
description: Pick the next unchecked item from the todo file and implement it following the plan.
disable-model-invocation: true
model: sonnet
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper script to load state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"
```

This gives you `slug`, `build_timestamp`, and `paths.*` — use `paths.todo` and `paths.plan` directly.

Before starting the loop, read these once:
- the `dev` convention (resolved via the lookup in `plugin-main.md`) — code style and quality rules
- the `testing` convention — test requirements
- the `git` convention — commit message format
- `paths.plan` in full — overview, quality gates, dependency graph, and step structure. You will NOT re-read the full plan inside the loop.
- the `## Context` block from `paths.session_log` (Block Reading Pattern from `plugin-main.md`), if present and not `STATUS: NONE` — use the reuse candidates and local conventions it documents when implementing each todo item.

Repeat the following loop until no unchecked items remain — do not wait for user approval between iterations:

**Each iteration:**
1. Open the file at `paths.todo` and pick the **first unchecked item** (one item only).
2. Work from the matching `### Prompt N:` section of the plan **already in context** — extract the
   step number N from the todo item (e.g., "Step 3: ..." → N=3) and use that section. Do not re-read
   or re-slice `paths.plan`; it was read in full before the loop.
3. Carefully plan your approach before touching any code — think through edge cases, dependencies, and impact on existing code.
4. Implement the item — write robust, readable code, add tests, verify tests pass.
5. Mark the item as checked (`- [x]`) in the todo file immediately after completing it.
6. Commit your changes following the `git` convention (resolved via the lookup in `plugin-main.md`). Use `feat:` for new functionality, `fix:` for bug corrections within the feature. Do **not** stage anything in `.bf/sessions/`.
7. Go back to step 1.
