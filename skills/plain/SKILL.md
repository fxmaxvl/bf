---
name: plain
description: "Use when existing prose should read plain and human — 'make this not sound like AI', 'rewrite this in plain language', 'clean up this README / PR description / error messages', 'apply STE', 'de-slop this'. Rewrites a file or pasted text under the prose convention (ASD-STE100 Simplified Technical English): short active sentences, short common words, no marketing words, no em dashes. Prose only; code, identifiers and commands stay untouched. Not for SKILL.md or other model-facing files, marketing copy, essays, or shortening a doc (bf:essence)."
model: sonnet
disable-model-invocation: false
argument-hint: "<file path | pasted text> [strict | flavored]"
allowed-tools: Read, Edit, Write, Bash(bash *), Bash(git *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Rewrite existing prose into plain technical English under the `prose` convention. The convention governs the text bf writes. This skill rewrites text that already exists.

## On Invocation

Print banner (plain text):

```
── bf:plain ─────────────────────────────────────────────
```

Read the input from `$ARGUMENTS`:

- **A file path** that exists: the target is that file.
- **Other text:** the target is that pasted text.
- **Nothing:** ask one question for the file or the text, then wait.

A trailing `strict` or `flavored` token sets the mode. Without it, pick the mode from the text by the Modes section of `prose.md`. State the pick in one line: `Mode: strict (runbook steps)`.

## Phase 1 — Load

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/scan-conventions/scripts/resolve-conventions.sh" prose
```

Read the path it prints. A project or user `prose.md` replaces the plugin default.

## Phase 2 — Rewrite

Rewrite the prose only. Do not change these:

- fenced code blocks and inline code
- identifiers, commands, file paths, links and URLs
- front-matter, and heading text that other links anchor to
- quoted material from other sources

Keep the meaning. Do not add a fact, and do not drop one. If a passage states no fact, remove it, and remove its heading if the section is then empty. Name it in the summary so the author can restore it from git. Do not leave it as it was, and do not invent content to fill it.

If the text already passes the self-lint, leave it as it is. Second-language and terse technical prose get minimal edits.

## Phase 3 — Self-lint

Run the Self-lint checklist from `prose.md` on the result. Fix each failure, then run the checklist again.

## Phase 4 — Deliver

**Pasted text:** print only the rewritten text. No preamble and no closing remarks.

**A file:**

1. Print a short change summary: sentences split, words replaced, passives made active, em dashes and semicolons removed, hollow passages flagged.
2. State the effect in one line: `This rewrites README.md in place.`
3. Edit the file in place. Git is the undo, so do not write a copy under `.bf/`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| The target is a code file | Rewrite only comments and user-facing messages in strings. If the intent is unclear, ask one question first. |
| The target is a `SKILL.md`, a convention, or an agent prompt | Say that model-facing files are out of scope. Continue only if the user insists. |
| The path does not exist and the argument looks like a path | Say that the file was not found. Do not rewrite the path string as text. |
| A rule conflicts with a required format (headings, tables, fixed strings) | The format wins. |
| The file has uncommitted changes | Say so in the effect line, because git cannot undo the rewrite cleanly. |
| The file is very large (more than about 1500 lines) | Rewrite one section at a time and report progress after each section. |
| The text is marketing copy or an essay | Say that STE strips voice and ask one question: continue or stop. |
