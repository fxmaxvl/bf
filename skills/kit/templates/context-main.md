# {{KIT_NAME}} — Main Context

{{KIT_DESCRIPTION}}

Every skill in this kit reads this file first and applies it throughout.

**Source repo:** `{{KIT_SOURCE_DIR}}` — the utility skills make every edit to the kit here.

## Interaction

- **Ask ONE question at a time.** Never batch questions. Ask the first, wait for the answer, then ask the next. This holds in every phase of every skill.
- **Ask rather than assume** when the answer changes what gets produced.
- **Restate a wide effect before acting on it** — overwriting a file, deleting, publishing — in one line.

## Prose

Read `${CLAUDE_PLUGIN_ROOT}/context/prose.md` and apply it to every piece of prose a skill writes for people: chat replies, reports, documents, and the sample output inside skill files. It does not govern code or the instructions in skill files. A skill's fixed structure (headings, table columns, keys) wins over it. When a skill spawns an agent whose output reaches people, add one line to the agent's prompt: "Apply the rules in `${CLAUDE_PLUGIN_ROOT}/context/prose.md` to all prose you return."

## Purpose

<!-- What this kit exists to do, and the outcome a good run produces. -->

## Perspective

<!-- Whose eyes the skills look through (role, seniority, stakes) and who reads the output. -->

## Frameworks & Methods

<!-- Named frameworks, models, and checklists the skills apply, with one line on when each fits. -->

## Output Style

<!-- Formats, structure, length, tone, and templates every output follows. -->

## Terminology

<!-- Domain terms used with a specific meaning in this kit. -->

## Knowledge

Reference material lives in `knowledge/`, next to the `context/` folder holding this file. `knowledge/index.md` lists each file with one line on what it covers. Read only the files relevant to the task at hand.

## Kit Skills

<!-- One line per skill: `/{{KIT_NAME}}:<skill>` — when to use it. Kept current by write-skill and adopt-skill. -->

- `/{{KIT_NAME}}:write-skill` — add a new skill to this kit, or take one from `BACKLOG.md`.
- `/{{KIT_NAME}}:adopt-skill` — adapt a skill from elsewhere into this kit.
- `/{{KIT_NAME}}:update-context` — revise this context or `context/prose.md`, or add material to `knowledge/`.
