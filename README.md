# bf (<B>uild<F>eature)

## Why bf?

Most AI coding tools jump straight to writing code. That works for small tasks — but for anything non-trivial, skipping the thinking phase is where bugs, rework, and scope creep come from.

bf enforces a structured workflow between you and Claude: clarify the idea first, produce a spec, review the design for architectural gaps, plan the implementation as a TDD blueprint, execute it, verify tests and lint pass, then open the PR. Each step is a checkpoint — Claude moves forward automatically where it can, and stops for your approval where it matters.

**The result:** less rework, fewer review surprises, and a paper trail (spec, plan, todo list) that survives context resets.

**Two modes:**
- **Full** — for new features: brainstorm → spec → design review → plan → execute → verify → PR
- **Quick** — for bugfixes and small changes: refine → plan → execute → verify → PR

Also includes a standalone design tool (`/bf:design`) for producing shareable system design documents — useful before any code is written, or when you need to align with teammates first.

## What's inside

| Command | Description |
|---------|-------------|
| `/bf:full <idea>` | brainstorm → spec → review → plan → execute → verify → finalize |
| `/bf:quick <idea>` | refine → plan → execute → verify → finalize |
| `/bf:design <idea>` | Interactive Q&A → shareable system design document |
| `/bf:gh` | Pick a GitHub issue → kick off full or quick workflow |
| `/bf:jira` | Pick a Jira ticket → kick off full or quick workflow |
| `/bf:discuss <question>` | Explore a question or design decision via dialogue before committing to a direction |
| `/bf:session-summary` | Generate a summary of the current session |

## Installation

In Claude:
```bash
/plugin marketplace add fxmaxvl/bf
/plugin install bf@fxmavl
```

Or to test locally without installing:

```bash
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

**Overriding per project:** drop a `.claude/conventions/<name>.md` in your project root — it takes precedence over the installed base conventions automatically.

## Requirements

- [Claude Code](https://claude.ai/code)
- `gh` CLI (for `/bf:gh` and PR creation)
- Jira MCP server configured (for `/bf:jira`)
- Excalidraw MCP server (optional, for diagrams in `/bf:design`)
