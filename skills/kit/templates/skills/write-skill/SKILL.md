---
name: write-skill
description: Use when asked to add a skill to the {{KIT_NAME}} kit, write a new {{KIT_NAME}} skill, or pick up an item from the kit backlog.
model: opus
disable-model-invocation: false
argument-hint: "[skill idea, name, or backlog item]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *)
---

Read `${CLAUDE_PLUGIN_ROOT}/context/main.md` first — it holds the kit's purpose, perspective, frameworks, output style, and the one-question-per-turn rule.

Author a new skill for this kit, from a rough idea to a working `skills/<name>/SKILL.md` in the kit's source repo.

`<KIT_SRC>` stands for the **Source repo** path in `context/main.md`; substitute that literal path wherever `<KIT_SRC>` appears below. Every write goes under `<KIT_SRC>`.

## On Invocation

Print banner (plain text):

── {{KIT_NAME}}:write-skill ─────────────────────────────

If `<KIT_SRC>` does not exist, the kit has moved: ask for its current path (one question), update the **Source repo** line in `<new path>/context/main.md` and the paths under § Install in `<new path>/README.md`, then use the new path as `<KIT_SRC>`.

With no argument, read `<KIT_SRC>/BACKLOG.md`; if it has items, offer them plus "something new" as one question.

## Phase 1 — Gather

Ask ONE question at a time. Stop as soon as the answer is evident from the idea, the backlog entry, or the main context.

1. **What should the skill do?** — the job, the phrase that should trigger it, and what it hands back.
2. **What does it take in?** — a document, a URL, a company name, files from `knowledge/`, nothing.
3. **What does it produce, and in what shape?** — a report, a plan, a deck, a review; check **Output Style** in the main context before asking.
4. **Interactive or autonomous?** — does it interview, or run straight through?
5. **Model?** — default `sonnet`; `opus` for multi-step judgement; `haiku` for cheap mechanical work.

## Phase 2 — Draft

If `<KIT_SRC>/skills/<name>/` exists, ask whether to overwrite or rename (one question).

Read `<KIT_SRC>/templates/skill-skeleton.md` with the Read tool and follow it: copy its fenced template to `<KIT_SRC>/skills/<name>/SKILL.md`, fill every placeholder, and apply its path rule.

Domain logic belongs in the skill; facts that several skills share belong in the main context or `knowledge/`. Point at them instead of copying them in.

## Phase 3 — Review & Register

Check the draft, fixing every gap:

- [ ] Frontmatter complete: `name`, `description`, `model`, `disable-model-invocation`, `argument-hint`, `allowed-tools`.
- [ ] The first line after the frontmatter reads the main context.
- [ ] Every interactive step asks one question, then waits.
- [ ] The description starts with "Use when…" and names trigger situations, not internals.
- [ ] A banner is printed before any substantive work.
- [ ] An `## Edge Cases & Errors` table is present.
- [ ] The path rule holds: the Grep tool finds no occurrence of the literal `<KIT_SRC>` path in `<KIT_SRC>/skills/<name>/SKILL.md`.

Then register the skill:

1. Add `/{{KIT_NAME}}:<name>` with one line on when to use it under **Kit Skills** in `<KIT_SRC>/context/main.md`.
2. Add a row to the `## Skills` table in `<KIT_SRC>/README.md`.
3. If it came from `<KIT_SRC>/BACKLOG.md`, remove that entry.
4. Commit locally: `git -C "<KIT_SRC>" add -A && git -C "<KIT_SRC>" commit -m "feat: add <name> skill"`.

Finish by pointing at **Picking up changes** in `<KIT_SRC>/README.md`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Idea overlaps an existing kit skill | Say which one; ask whether to extend it or write a separate skill (one question). |
| Still ambiguous after five questions | Draft with best guesses and mark them `<!-- TODO: clarify -->`. |
| The skill needs a fact only the user has | Ask it now, and if it is shared across skills, offer to add it to the main context via update-context. |
| `git commit` fails (no git identity) | Leave the files written and tell the user the one `git config` command to run. |
