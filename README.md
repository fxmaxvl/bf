# bfeature

A Claude Code skill plugin that turns a raw idea into a merged pull request through a structured, AI-guided workflow.

Instead of jumping straight to code, bfeature walks you through the right steps: clarifying the idea, producing a spec, reviewing the design, planning the implementation, executing it, verifying quality, and finalizing the PR. Each phase is a quality gate — you stay in control, Claude does the heavy lifting.

**Two modes:**
- **Full** — for new features: brainstorm → spec → design review → plan → execute → verify → PR
- **Quick** — for bugfixes and small changes: refine → plan → execute → verify → PR

Also includes a standalone design tool (`/bfeature:design`) for producing shareable system design documents before any code is written.

## What's inside

| Command | Description |
|---------|-------------|
| `/bfeature:menu` | List all available commands |
| `/bfeature:full <idea>` | brainstorm → spec → review → plan → execute → verify → finalize |
| `/bfeature:quick <idea>` | refine → plan → execute → verify → finalize |
| `/bfeature:design <idea>` | Interactive Q&A → shareable system design document |
| `/bfeature:gh` | Pick a GitHub issue → kick off full or quick workflow |
| `/bfeature:jira` | Pick a Jira ticket → kick off full or quick workflow |
| `/bfeature:session-summary` | Generate a summary of the current session |

## Installation

```bash
claude plugin install fxmaxvl/bfeature
```

Or to test locally without installing:

```bash
claude --plugin-dir ./path/to/bfeature
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
- `gh` CLI (for `/bfeature:gh` and PR creation)
- Jira MCP server configured (for `/bfeature:jira`)
- Excalidraw MCP server (optional, for diagrams in `/bfeature:design`)
