# bfeature Plugin — Shared Conventions

These rules apply to every skill in this plugin.

## Interaction

- **Always ask for clarification** rather than making assumptions.
- **Ask ONE question at a time.** Never batch multiple questions into a single response. If you have several things to clarify, ask the first, wait for the answer, then ask the next. This is a hard rule, not a suggestion. **It applies at every point in every skill and sub-skill — including brainstorm, gather, refine, and any interactive phase. Mid-workflow does not exempt you from this rule.**

## Convention Lookup

When you need a convention file, resolve it using this 3-step lookup — **first match wins, fully replaces the plugin default**:

1. `<project_root>/.claude/bf-conventions/<name>.md` — use `git rev-parse --show-toplevel` to find project root
2. `~/.claude/bf-conventions/<name>.md`
3. `${CLAUDE_PLUGIN_ROOT}/conventions/<name>.md`

The available convention names and when to use each:

| Action | Convention name |
|--------|----------------|
| Writing or modifying code | `dev` |
| Writing or modifying tests | `testing` |
| Committing | `git` |
| Designing architecture | `architecture` |
| TypeScript / JavaScript work | `typescript` |
| Reviewing code | `code-review` |
| Running or documenting quality gates | `quality-gates` |
