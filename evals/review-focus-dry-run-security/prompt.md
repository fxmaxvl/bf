---
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Skill]
---

/bf:review --dry-run --focus security

(Eval harness: stop after the dry-run preview. Where a phase would ask a question, take the obvious default.)
