---
name: update-context
description: Use when the {{KIT_NAME}} kit's main context needs to change — a new framework, a refined perspective, a style rule, new terminology — or when adding notes, documents, or URLs to the kit's knowledge.
model: sonnet
disable-model-invocation: false
argument-hint: "[what changed, or a file/URL to add to knowledge]"
allowed-tools: Read, Write, Edit, Glob, Grep, WebFetch, Bash(git *), Bash(cp *), Bash(mkdir *)
---

Read `${CLAUDE_PLUGIN_ROOT}/context/main.md` first.

Revise the kit's shared context or grow its knowledge base, so every skill picks up the change.

`<KIT_SRC>` stands for the **Source repo** path in `context/main.md`; substitute that literal path wherever `<KIT_SRC>` appears below. All edits go under `<KIT_SRC>`.

## On Invocation

Print banner (plain text):

── {{KIT_NAME}}:update-context ──────────────────────────

If `<KIT_SRC>` does not exist, the kit has moved: ask for its current path (one question), update the **Source repo** line in `<new path>/context/main.md` and the paths under § Install in `<new path>/README.md`, then use the new path as `<KIT_SRC>`.

Classify the argument:
- a file path or URL → **Knowledge Mode**
- anything else → **Context Mode**
- nothing → ask what changed (one question)

## Context Mode

1. Name the section(s) of `context/main.md` the change belongs in.
2. If the change contradicts what is already there, quote the existing line and ask which wins (one question).
3. Edit only those sections. Keep each one tight: rules and facts, not essays.
4. Grep `<KIT_SRC>/skills/*/SKILL.md` for anything the change makes stale (a framework name, a format, a term). List the hits and ask whether to update them now (one question). If yes, edit each one.

## Knowledge Mode

For each source:

- **Local text or Markdown file** → copy it into `<KIT_SRC>/knowledge/`.
- **PDF, slides, or URL** → read it and write `<KIT_SRC>/knowledge/<slug>.md`: a distilled summary covering the frameworks, models, definitions, and examples the kit's skills would apply, with the source path or URL at the top. Keep the original only if the user asks.
- **Directory** → list its files and ask which to bring in (one question).

Then add one line per new file to `<KIT_SRC>/knowledge/index.md`: `- [<title>](<file>) — <what it covers, when a skill should read it>`.

If a source introduces a framework or term the main context lacks, offer to add it (one question).

## Finish

Commit locally: `git -C "<KIT_SRC>" add -A && git -C "<KIT_SRC>" commit -m "docs: <what changed>"`. Then point at **Picking up changes** in `<KIT_SRC>/README.md`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Source unreadable (private URL, scanned PDF) | Say so and ask the user to paste or export the text. |
| A knowledge file with that name exists | Ask whether to replace it or keep both (one question). |
| Change belongs to a single skill, not the kit | Suggest editing that skill instead, and do it if the user agrees. |
| `git commit` fails | Leave the edits and report the error. |
