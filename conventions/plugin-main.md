# feature Plugin — Shared Conventions

These rules apply to every skill in this plugin.

## Interaction

- **Always ask for clarification** rather than making assumptions.
- **Ask ONE question at a time.** Never batch multiple questions into a single response. If you have several things to clarify, ask the first, wait for the answer, then ask the next. This is a hard rule, not a suggestion. **It applies at every point in every skill and sub-skill — including brainstorm, gather, refine, and any interactive phase. Mid-workflow does not exempt you from this rule.**

## Convention Lookup

When you need a convention file, resolve it using this 3-step lookup — **first match wins, fully replaces the plugin default**:

1. `<project_root>/.bf/conventions/<name>.md` — use `git rev-parse --show-toplevel` to find project root
2. `~/.bf/conventions/<name>.md`
3. `${CLAUDE_PLUGIN_ROOT}/conventions/<name>.md`

The available convention names and when to use each:

## Custom Convention Discovery

Beyond the predefined convention names above, users may define arbitrarily-named convention files (e.g. `api-style.md`, `monorepo-rules.md`) in either of:

- `<project_root>/.bf/conventions/` — project-local custom conventions
- `~/.bf/conventions/` — user-global custom conventions

When working on a task where such conventions might apply, run the discovery script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/scan-conventions/scripts/discover-conventions.sh"
```

The script returns a JSON array `[{filename, tier, first_heading, path}]`. Read each file that is relevant to the current task and apply its rules alongside any predefined convention files. Project tier wins when the same filename exists in both tiers.

Alternatively, invoke `/bf:scan-conventions [task description]` — it handles discovery + relevance filtering and returns a structured list of matched files.

## Artifact Layout

Each session produces two files:

| File | Key | Contents |
|------|-----|----------|
| `<prefix>-session-log.md` | `paths.session_log` | Persistent blocks: Spec, Plan, Todo, Backlog, Deployment |
| `<prefix>-temp.md` | `paths.temp` | Ephemeral blocks: QA, Design Report, Implementation Review, Complexity Report |

`paths.spec`, `paths.plan`, etc. are **aliases** — they resolve to the same physical file (`session_log` or `temp`). Use `paths.block_<name>` for the matching block header (e.g. `paths.block_spec` = `## Spec`).

### Block Reading Pattern

To read a specific artifact from a merged file:

1. Grep `paths.<artifact>` for `^<paths.block_<artifact>>` to find the start line
2. Grep `paths.<artifact>` for the next `^## ` after that line to find the end (use EOF if it's the last block)
3. Read `paths.<artifact>` with `offset=<start>` and `limit=<end - start>`

### Block Writing Pattern

To write an artifact block:

1. If the physical file doesn't exist: create it with `<paths.block_<artifact>>\n\n<content>`
2. If it exists but the block header is absent: append `\n\n<paths.block_<artifact>>\n\n<content>`
3. If the block header already exists: replace the block content in place (edit from header to next `## ` or EOF)

Do **not** overwrite the entire file — other blocks may already be present.

The available convention names and when to use each:

| Action | Convention name |
|--------|----------------|
| Writing or modifying code | `dev` |
| Writing or modifying tests | `testing` |
| Committing | `git` |
| Designing architecture | `architecture` |
| TypeScript / JavaScript work | `typescript` |
| Reviewing code | `code-review` |
