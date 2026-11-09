---
name: plain
description: "Use when existing prose should read plain and human. Triggers: 'make this not sound like AI', 'rewrite this in plain language', 'clean up this README / PR description / error messages', 'apply STE', 'de-slop this'. Add the detect token for 'is this AI slop', 'scan this without rewriting', 'flag the slop': it names each pattern and edits nothing. Rewrites a file or pasted text under the prose convention (ASD-STE100 Simplified Technical English): short active sentences, short common words, no marketing words, no em dashes. Prose only. Code, identifiers and commands stay untouched. Not for SKILL.md or other model-facing files, marketing copy, essays, or shortening a doc (bf:essence)."
model: sonnet
disable-model-invocation: false
argument-hint: "<file path | pasted text> [strict | flavored | detect]"
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

A trailing `detect` token selects the detect job: run Phase 1 and the Detect phase, then stop. Detect never rewrites, so it ignores a `strict` or `flavored` token. Any other job runs every phase.

A trailing `strict` or `flavored` token sets the mode. Without it, and outside the detect job, pick the mode from the text by the Modes section of `prose.md`. State the pick in one line: `Mode: strict (runbook steps)`.

## Phase 1 — Load

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/scan-conventions/scripts/resolve-conventions.sh" prose
```

Read the path it prints. A project or user `prose.md` replaces the plugin default.

Then take the "before" lint result. For a file target, run the command below. For a code file, add `--mode comment --ext <ext>` so the counts cover comments only.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plain/scripts/prose-lint.sh" <file> --rules <resolved path> --format json
```

For pasted text, pass the text on stdin with `-` as the input. The command must start with `bash`, because `allowed-tools` grants `Bash(bash *)` only, and a `printf` pipe would hit a permission prompt:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plain/scripts/prose-lint.sh" - --rules <resolved path> --format json <<'BF_TEXT'
<the text>
BF_TEXT
```

Keep the `hard` counts and the `summary` as the "before" result. Exit 1 is a normal result here, not a failure. Exit 2 means no result: say so in one line and continue.

## Detect

Run this phase only for the detect job. Print `Job: detect`. Do not edit, score or guess who wrote the text.

1. Run the Phase 1 lint with `--format text` in place of `--format json`. Each output line is `<line>: <marker>: <text>`. Exit 1 is a normal result.
2. For each finding, read the line by its number and quote it. For pasted text, the number counts lines of the pasted text.
3. Read the PATTERNS and STRUCTURE groups of `prose.md`. Add the patterns the lint cannot see: colon reveals, negative listing, dramatic fragments, fake-profound kickers, summary recaps, synonym cycling, robotic rhythm, and the formatting rule. Also apply Self-lint item 9, the portability test.
4. Print one row per finding: the pattern name, the line number, the quoted line, and the fix in a few words.
5. End with one line that offers a rewrite, then stop.

If a text has no finding, say so in one line. Hard markers (em dash, semicolon, contraction) appear in the rows as findings like any other.

## Phase 2 — Rewrite

Rewrite the prose only. Do not change these:

- fenced code blocks and inline code
- identifiers, commands, file paths, links and URLs
- front-matter, and heading text that other links anchor to
- quoted material from other sources

Keep the meaning. Do not add a fact, and do not drop one. If a passage states no fact, remove it, and remove its heading if the section is then empty. Name it in the summary so the author can restore it from git. Do not leave it as it was, and do not invent content to fill it.

The lint count is advisory. Do not change code, commands or quoted material to bring the count to zero.

If the text already passes the self-lint, leave it as it is. Second-language and terse technical prose get minimal edits.

## Phase 3 — Self-lint

Run the lint command from Phase 1 on the result for the "after" result. The edit is not written yet, so pass the rewritten text on stdin with `-` for both a file and pasted text. Do not lint the file path here, because the file still holds the old text.

Run the Self-lint checklist from `prose.md` on the result for the rules the script cannot check. This includes item 9 (portability) and item 10 (read aloud). Fix each failure, then run the checklist and the lint again.

## Phase 4 — Deliver

**Pasted text:** print only the rewritten text. No preamble and no closing remarks.

**A file:**

1. Print a short change summary: sentences split, words replaced, passives made active, em dashes and semicolons removed, hollow passages flagged. Add one line with both lint counts, for example `Lint: 4 em dashes, 2 semicolons before, 0 after`.
2. State the effect in one line: `This rewrites README.md in place.`
3. Edit the file in place. The "after" counts come from the Phase 3 lint of the rewritten text. Git is the undo, so do not write a copy under `.bf/`.

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
