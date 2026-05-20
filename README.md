# bf (Build Feature)

## Why bf?

Most AI coding tools jump straight to writing code. That works for small tasks — but for anything non-trivial, skipping the thinking phase is where bugs, rework, and scope creep come from.

bf enforces a structured workflow between you and Claude: clarify the idea first, produce a spec, review the design for architectural gaps, plan the implementation as a TDD blueprint, execute it, verify tests and lint pass, then open the PR. Each step is a checkpoint — Claude moves forward automatically where it can, and stops for your approval where it matters.

**The result:** less rework, fewer review surprises, and a paper trail (spec, plan, todo list) that survives context resets.

**Three modes:**
- **Full** — for new features: brainstorm → spec → design review → plan → execute → verify → PR
- **Quick** — for bugfixes and small changes: refine → plan → execute → verify → PR
- **Micro** — for focused refactors: clarify only if needed, execute with complexity and quality guards

Also includes a standalone design tool (`/bf:design`) for producing shareable system design documents — useful before any code is written, or when you need to align with teammates first.

## What's inside

| Skill | Kind | What it does |
|---|---|---|
| `/bf:feature <idea>` | Workflow | Take a rough idea through brainstorm, spec, design review, plan, execute, verify, and finalize — with checkpoints between phases |
| `/bf:quick <idea>` | Workflow | Plan-to-code for small changes and bugfixes — refine, plan, execute, verify, finalize |
| `/bf:micro <idea>` | Workflow | Focused refactor workflow with complexity and quality guards — clarify only if needed, then execute |
| `/bf:design <idea>` | Utility | Turn an idea into a shareable system-design document via interactive Q&A — standalone, no git/PR |
| `/bf:gh` | Utility | Pick or create a GitHub issue and kick off a full or quick workflow |
| `/bf:jira` | Utility | Pick a Jira ticket and kick off a full or quick workflow |
| `/bf:review [PR# \| files]` | Utility | Review code (current branch diff, a PR by number, or specific files) against conventions and the complexity gate |
| `/bf:discuss <question>` | Utility | Explore a question or design decision via dialogue before committing to a direction |
| `/bf:session-summary` | Utility | Generate a summary of the current session |

## Getting started

### Add the marketplace

Register the `bf` marketplace with Claude Code (one-time setup):

```shell
/plugin marketplace add fxmaxvl/bf
```

### Install

```shell
/plugin install bf@fxmaxvl
```

Then run `/reload-plugins` to activate it.

### Update

Fetch the latest plugin listings and update installed plugins:

```shell
/plugin marketplace update fxmaxvl
```

### Uninstall

```shell
/plugin uninstall bf@fxmaxvl
```

### Test locally without installing

```shell
claude --plugin-dir ./path/to/bf
```

## Conventions

The `conventions/` directory contains language- and action-specific guidelines Claude reads before acting:

- `dev.md` — writing and modifying code
- `testing.md` — writing and modifying tests
- `git.md` — commit messages (Conventional Commits)
- `architecture.md` — architectural decisions
- `code-review.md` — reviewing code
- `typescript.md` — TypeScript/JavaScript specifics

**Overriding conventions:** bf supports a 3-level lookup for each convention file (first match wins, fully replaces the plugin default):

1. `<project_root>/.bf/conventions/<name>.md` — project-local override
2. `~/.bf/conventions/<name>.md` — user-global override
3. Plugin default (bundled in `conventions/`)

To override a convention, create the `.bf/conventions/` directory in the appropriate location and drop in files using the same names as above (e.g., `dev.md`, `git.md`). A matching file fully replaces the plugin default — there is no merging.

## Requirements

- [Claude Code](https://claude.ai/code)
- `gh` CLI (for `/bf:gh` and PR creation)
- Jira MCP server configured (for `/bf:jira`)
- Excalidraw MCP server (optional, for diagrams in `/bf:design`)
