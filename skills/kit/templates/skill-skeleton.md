# Skill Skeleton

Template for every skill in the {{KIT_NAME}} kit. Copy the fenced block into `skills/<name>/SKILL.md`, fill every placeholder, and delete lines that do not apply.

Path rule: inside a skill, refer to kit files as `${CLAUDE_PLUGIN_ROOT}/<path>`, written literally. Claude Code expands it when the skill loads, so never write the kit's absolute path into a skill.

````markdown
---
name: <name>
description: Use when <trigger situations, phrased as the user would say them>.
model: <opus | sonnet | haiku>
disable-model-invocation: false
argument-hint: "[<what the user passes>]"
allowed-tools: <only what the skill needs, e.g. Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, Bash(git *)>
---

Read `${CLAUDE_PLUGIN_ROOT}/context/main.md` first.

<One line: what this skill does and when to use it.>

## On Invocation

Print banner (plain text):

── {{KIT_NAME}}:<name> ─────────────────────────────

<Parse the argument; ask ONE question for anything missing.>

## Phase 1 — <name>

<Steps. Name the frameworks from the main context it applies and the knowledge files it reads.>

## Phase 2 — <name>

<...>

## Output

<Exact shape of the result and where it is written.>

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| <condition> | <handling> |
````
