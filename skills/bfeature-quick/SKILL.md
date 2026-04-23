---
name: bfeature-quick
description: Quick workflow (refine → plan → execute → verify → finalize) — skips brainstorm and review-design.
argument-hint: [idea description, Jira ticket URL, or GH-ISSUE:<number>]
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), mcp__*__jira__*
---

Run the `bfeature-full` workflow in quick mode.

1. Read `~/.claude/skills/bfeature-full/SKILL.md`. If not found, try `skills/bfeature-full/SKILL.md`.
2. Follow its instructions with `--quick` prepended to `$ARGUMENTS`.

Here is the idea:
$ARGUMENTS
