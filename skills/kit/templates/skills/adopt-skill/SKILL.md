---
name: adopt-skill
description: Use when the user points at an existing skill — a URL, a local path, or a skill from another plugin — and wants it adapted into the {{KIT_NAME}} kit.
model: opus
disable-model-invocation: false
argument-hint: "<url | path> [what to keep, drop, or change]"
allowed-tools: Read, Glob, Grep, WebFetch, Bash(gh *), Bash(git *), Write, Edit
---

Read `${CLAUDE_PLUGIN_ROOT}/context/main.md` first.

Take a skill from somewhere else and rework it for this kit's purpose, perspective, and output style, then hand it to write-skill's drafting procedure.

`<KIT_SRC>` stands for the **Source repo** path in `context/main.md`; substitute that literal path wherever `<KIT_SRC>` appears below.

## On Invocation

Print banner (plain text):

── {{KIT_NAME}}:adopt-skill ─────────────────────────────

If `<KIT_SRC>` does not exist, the kit has moved: ask for its current path (one question), update the **Source repo** line in `<new path>/context/main.md` and the paths under § Install in `<new path>/README.md`, then use the new path as `<KIT_SRC>`.

Parse the argument: the first token that is a URL or an existing path is the **source**; the rest is the **instructions**. If the source is missing, ask for it (one question). Missing instructions mean "adopt the whole skill".

## Phase 1 — Fetch

- `github.com/<org>/<repo>/blob/<ref>/<path>` → `gh api -H 'Accept: application/vnd.github.raw' "repos/<org>/<repo>/contents/<path>?ref=<ref>"`; fall back to WebFetch.
- Other URL → WebFetch.
- Local path → Read. If it is a skill directory, read `SKILL.md` and list any `scripts/` or `templates/` beside it.

Print one line: `Fetched: <source> (<N> lines)`.

## Phase 2 — Analyze

Print a compact analysis:

```
## Source Analysis
Source: <source>
Purpose: <one sentence>
Keep: <sections/phases kept, per instructions>
Drop: <sections dropped, and why>
Kit fit:
- Perspective: <how the main context's perspective changes it>
- Frameworks: <main-context frameworks it should apply>
- Output style: <changes needed to match the kit's output style>
- Knowledge: <knowledge/ files it should read>
- Foreign references: <paths, plugin names, tools, or conventions from the source that must go>
- Batched questions: <places the source asks several questions at once>
```

Proceed without waiting for approval, unless the source clearly doesn't fit the kit's purpose. In that case, say so and ask whether to continue (one question).

## Phase 3 — Hand Off

Write a design spec covering triggers, phases, inputs, output, model, tools, and edge cases, all in this kit's terms. Then read `<KIT_SRC>/skills/write-skill/SKILL.md` and follow it from **Phase 2 — Draft** onward, using the spec as the gathered answers. Ask Phase 1 questions only for what the spec leaves open.

Every foreign reference from the analysis must be gone from the drafted skill: no other plugin's paths, banners, or convention files.

If the source shipped `scripts/` or `templates/`, copy them into `<KIT_SRC>/skills/<name>/` and rewrite their paths per the path rule in `<KIT_SRC>/templates/skill-skeleton.md`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Private repo, `gh` unauthenticated, WebFetch fails | Ask the user to paste the skill content. |
| Source uses tools this environment lacks | Name them in the analysis and propose the closest available tool. |
| Name collides with an existing kit skill | write-skill's overwrite-or-rename question handles it. |
| Source is not a skill (an article, a prompt) | Treat it as raw material for the spec and say so in the analysis. |
