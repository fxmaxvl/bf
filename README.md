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

| Skill | Kind | What it does | When to use |
|---|---|---|---|
| `/bf:feature <idea>` | Workflow | Full brainstorm → spec → design → plan → execute → verify flow with checkpoints | You have a new idea and want to think it through before touching code |
| `/bf:quick <idea>` | Workflow | Lightweight plan → execute → verify loop | You know roughly what needs doing and just want it done |
| `/bf:micro <idea>` | Workflow | Focused refactor with complexity and quality guards | Small, scoped change — one function, one file, clean it up |
| `/bf:bug-fix <symptoms>` | Workflow | Parallel root-cause hunt, decide-gated diagnose → fix, no user prompts | Something is broken and you want a fast autonomous fix |
| `/bf:autopilot [skill] <args>` | Workflow | Runs any bf skill end-to-end without stopping to ask you anything | You want to go fully hands-off — decide oracle handles every decision |
| `/bf:decide <question>` | Oracle | Single decisive verdict with rationale — weighs options, picks one, cites evidence | You need a quick call on one thing and trust a single opinion |
| `/bf:discuss <question>` | Oracle | Open dialogue to explore a question before committing to a direction | You're not ready to decide yet — you want to think out loud first |
| `/bf:consilium <question>` | Oracle | 3-critic council: one answers, two challenge from opposing angles, majority wins | The decision is high-stakes or contested and one opinion isn't enough |
| `/bf:design <idea>` | Utility | Shareable system-design doc with diagrams, via interactive Q&A | You need a design artifact — standalone, no git or PR involved |
| `/bf:adr-writer [title]` | Utility | Interactive Q&A to draft a numbered ADR citing only tracked source files | You need to record an architecture decision as a real project doc |
| `/bf:review [PR# \| files]` | Utility | Code review against bf conventions and the complexity gate | Before merging — or whenever you want a second set of eyes |
| `/bf:gh` | Utility | Pick or create a GitHub issue and kick off a workflow | Starting work from an issue tracker |
| `/bf:jira` | Utility | Pick a Jira ticket and kick off a workflow | Starting work from Jira |
| `/bf:write-skill [name]` | Utility | Author a new bf-style skill from scratch | You want to extend bf with a new skill |
| `/bf:onboard-skill <url> <instructions>` | Utility | Fetch an external skill, analyze what to port, adapt to bf conventions, and hand off to bf:write-skill | You want to steal a skill from another plugin and adapt it for bf |
| `/bf:scan-conventions [task]` | Utility | Discovers and filters user-defined custom conventions relevant to the current task. | Before acting on a task where project/user convention files beyond the predefined set might apply |
| `/bf:session-summary` | Utility | Summary of what happened this session | End of a work session — capture what changed and why |
| `/bf:gather <feature or PRD>` | Utility | Iterative requirements gathering and versioned PRD distillation across sessions | You have a fuzzy PRD and need to track open questions, scope a POC, and build a versioned source of truth |
| `/bf:research <topic>` | Utility | Decision-oriented researcher: clarifies usecase → issue → focus, gathers cited evidence, produces an Options + Recommendation report | You need prior art, library comparison, or decision support before building — and want a cited report saved to `.bf/research/` |
| `/bf:teach <topic>` | Utility | Stateful multi-session tutor: mission-grounded HTML lessons, reference docs, learning records, resources, and a glossary in a per-topic workspace, plus an optional learning profile that tailors lesson delivery | You want to deliberately learn a topic over time, not just get a one-off explanation |

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
