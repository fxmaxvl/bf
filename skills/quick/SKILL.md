---
name: quick
description: Quick workflow (refine → plan → execute → verify → finalize) — skips brainstorm and review-design.
argument-hint: [idea description, Jira ticket URL, or GH-ISSUE:<number>]
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), mcp__*__jira__*
---

Run the `full` workflow in quick mode.

1. Locate the full skill SKILL.md: `Glob("~/.claude/**/full/SKILL.md")`. Use the first result.
2. Read it and follow its instructions with `--quick` prepended to `$ARGUMENTS`.

Here is the idea:
$ARGUMENTS
