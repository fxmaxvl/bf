---
name: quick
description: Quick workflow (refine → plan → execute → verify → finalize) — skips brainstorm and review-design.
model: sonnet
argument-hint: [idea description, Jira ticket URL, or GH-ISSUE:<number>]
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), mcp__*__jira__*
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the `bfeature` workflow in quick mode.

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/bfeature/SKILL.md` and follow its instructions with `--quick` prepended to `$ARGUMENTS`.
2. Read it and follow its instructions with `--quick` prepended to `$ARGUMENTS`.

Here is the idea:
$ARGUMENTS
