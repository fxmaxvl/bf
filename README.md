# bfeature

A Claude Code skill plugin for the full feature development workflow — from idea to pull request.

## What's inside

| Skill | Command | Description |
|-------|---------|-------------|
| Menu | `/bfeature` | List all available commands |
| Full workflow | `/bfeature-full <idea>` | brainstorm → spec → review → plan → execute → verify → finalize |
| Quick workflow | `/bfeature-quick <idea>` | refine → plan → execute → verify → finalize |
| Design doc | `/bfeature-design <idea>` | Interactive Q&A → shareable system design document |
| GitHub | `/bfeature-gh` | Pick a GitHub issue → kick off full or quick workflow |
| Jira | `/bfeature-jira` | Pick a Jira ticket → kick off full or quick workflow |
| Session summary | `/session-summary` | Generate a summary of the current session |

## Installation

```bash
git clone git@github.com:fxmaxvl/bfeature.git
cd bfeature
cp -r skills/* ~/.claude/skills/
cp conventions/* ~/.claude/conventions/
cp CLAUDE.md ~/.claude/CLAUDE.md   # or merge manually if you already have one
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
- `gh` CLI (for GitHub integration)
- Jira MCP server configured (for `/bfeature-jira`)
- Excalidraw MCP server (optional, for diagrams in `/bfeature-design`)
