# bfeature Plugin — Shared Conventions

These rules apply to every skill in this plugin.

## Interaction

- **Always ask for clarification** rather than making assumptions.
- **Ask ONE question at a time.** Never batch multiple questions into a single response. If you have several things to clarify, ask the first, wait for the answer, then ask the next. This is a hard rule, not a suggestion. **It applies at every point in every skill and sub-skill — including brainstorm, gather, refine, and any interactive phase. Mid-workflow does not exempt you from this rule.**

## Conventions

Convention files are bundled with this plugin. Skills reference them directly using `${CLAUDE_PLUGIN_ROOT}/conventions/`.

| Action | Convention file |
|--------|----------------|
| Writing or modifying code | `${CLAUDE_PLUGIN_ROOT}/conventions/dev.md` |
| Writing or modifying tests | `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md` |
| Committing | `${CLAUDE_PLUGIN_ROOT}/conventions/git.md` |
| Designing architecture | `${CLAUDE_PLUGIN_ROOT}/conventions/architecture.md` |
| TypeScript / JavaScript work | `${CLAUDE_PLUGIN_ROOT}/conventions/typescript.md` |
| Reviewing code | `${CLAUDE_PLUGIN_ROOT}/conventions/code-review.md` |
