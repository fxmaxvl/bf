---
name: bfeature
description: Feature development workflow toolkit. Print available commands.
disable-model-invocation: true
---

## bfeature — available commands

| Command | Description |
|---------|-------------|
| `/bfeature-full <idea>` | Full workflow: brainstorm → spec → review → plan → execute → verify → finalize |
| `/bfeature-quick <idea>` | Quick workflow: refine → plan → execute → verify → finalize (skips brainstorm) |
| `/bfeature-design <idea>` | Interactive Q&A → shareable system design document. Optionally seeds bfeature. |
| `/bfeature-gh` | Pick a GitHub issue → full or quick bfeature workflow |
| `/bfeature-jira` | Pick a Jira ticket → full or quick bfeature workflow |
| `/session-summary` | Generate a summary of the current session |

Pass an idea directly: `/bfeature-full add dark mode support`
