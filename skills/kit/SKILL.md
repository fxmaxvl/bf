---
name: kit
description: Use when the user wants to build a standalone Claude Code plugin — a "kit" — for one purpose or domain (a course, a role, a recurring kind of work), e.g. "build me a kit for my CTO course", "make a plugin with skills for analysing startup strategies". Interviews for the kit's context, ingests reference material, agrees the skill roster, drafts the chosen skills, and leaves a git-initialised plugin outside bf that grows itself with its own write-skill, adopt-skill, and update-context.
model: opus
disable-model-invocation: false
argument-hint: "[what the kit is for, e.g. 'CTO course: strategy analysis, plans, decks']"
allowed-tools: Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, Bash
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Build a standalone, domain-focused Claude Code plugin: a main context, three utility skills that let the kit extend itself, and the domain skills you choose to draft now.

The kit is the deliverable: a plugin the user installs and keeps. So it is written to a directory the user picks rather than under `.bf/`. This is a named exception in plugin-main.md.

## On Invocation

Print banner (plain text):

── bf:kit ───────────────────────────────────────────────

## Phase 1 — Name & Place

Ask ONE question at a time, skipping any whose answer is already in the argument.

1. **Purpose** — what the kit is for, in a sentence.
2. **Name** — propose a kebab-case name derived from the purpose (e.g. `cto-course`). It becomes the skill namespace: `/cto-course:<skill>`.
3. **Location** — the default is `<cwd>/<name>/`. Accept another path.

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/kit/scripts/kit-scaffold.sh" probe --dir "<target>" --name <name>` and resolve the result, one question per problem:

- `nonempty: true` → choose another path or name. Never scaffold over existing files.
- `inside_repo: true` → warn that the kit will sit inside `<repo_root>` as an embedded repository, and ask: keep it there, or move it (suggest `<repo_root>/../<name>`)?
- `name_taken: true` → a plugin with that name is already installed, so the slash namespace would clash; suggest a suffixed name.
- `git_identity: false` → note that the final commit will need `git config user.name` / `user.email`; proceed.

## Phase 2 — Scaffold

State the effect in one line: *"this creates `<target>` with the kit skeleton and runs `git init`"*. Then run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/kit/scripts/kit-scaffold.sh" create --dir "<target>" --name <name> --description "<purpose, one line>"
```

`<KIT>` is `kit_dir` from the output: a plugin skeleton with `context/main.md`, `knowledge/index.md`, `BACKLOG.md`, `README.md`, `.claude-plugin/{plugin,marketplace}.json`, `templates/skill-skeleton.md`, and the utility skills `write-skill`, `adopt-skill`, and `update-context`. An `error` key in the output stops the run: report it and resolve it with one question.

The kit's own skills call this directory `<KIT_SRC>`, its **Source repo**. Wherever this skill follows one of them, `<KIT_SRC>` is `<KIT>`.

## Phase 3 — Context Interview

Fill `<KIT>/context/main.md` section by section. Ask ONE question per turn, and propose a concrete draft answer when you can, so the user edits rather than writes from scratch:

1. **Purpose** — the outcome a good run produces.
2. **Perspective** — whose eyes the skills use (e.g. a CTO reviewing a startup), and who reads the output.
3. **Frameworks & Methods** — the named models and checklists the work relies on (course frameworks, house methods).
4. **Output Style** — formats (report, plan, deck), structure, length, and tone.
5. **Terminology** — terms with a kit-specific meaning. Skip if none.

Write each answer into its section as soon as it is given. Rules and facts only, no transcript.

## Phase 4 — Materials

Ask whether there are materials to ground the kit: notes, slides, templates, articles, as files, folders, or URLs. If there are, ingest them exactly as `<KIT>/skills/update-context/SKILL.md` describes under **Knowledge Mode**, writing to `<KIT>/knowledge/`. Any framework or term a source introduces that the context lacks goes into `context/main.md` after one confirming question.

## Phase 5 — Skill Roster

Propose 3–7 domain skills that follow from the context. For each, give a kebab-case name and one line on when to use it. Fold in any skills the user already named (e.g. for a CTO course: strategy analysis, a strategy plan in the user's format, presentations, a CTO-perspective review). Present the roster and ask for additions, removals, or renames (one question). Repeat until the user accepts it.

Then ask a single multi-select question: **which skills to draft now**. The rest go to `<KIT>/BACKLOG.md` as `- **<name>** — <one line>`.

## Phase 6 — Draft Skills

For each skill chosen for drafting, one at a time, follow `<KIT>/skills/write-skill/SKILL.md` Phases 1–3:

- Treat the roster line and the context as answers already given, and ask only what they leave open.
- Skip the per-skill commit in its register step; Phase 7 makes one initial commit.

## Phase 7 — Finalize

1. Check the kit is self-contained. Both commands must print `clean`; fix every hit. The first catches bf references and unrendered placeholders. The second catches the kit's absolute path hard-coded into a skill, where `${CLAUDE_PLUGIN_ROOT}` belongs:
   ```bash
   command grep -rnE -e '(^|[^a-z])bf:' -e '\.bf/conventions' -e 'plugins/cache' -e '\{\{[A-Z_]+\}\}' "<KIT>" --exclude-dir=.git --exclude=.gitignore || echo clean
   command grep -rnF "<KIT>" "<KIT>/skills" || echo clean
   ```
2. Validate the manifests: `claude plugin validate "<KIT>"`, falling back to `python3 -m json.tool` on both JSON files if the CLI is unavailable.
3. State the effect in one line, then make the commit: `git -C "<KIT>" add -A && git -C "<KIT>" commit -m "feat: scaffold <name> kit"`.
4. Print a summary: the kit path, the skills drafted, the backlog items, and the install commands from `<KIT>/README.md` § Install. Remind the user that `/<name>:write-skill` with no argument picks up the backlog.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Target exists and is non-empty | Never scaffold over it; ask for another path or name. |
| Target is inside another git repo | Warn about the embedded repo; ask whether to keep it there or move it. |
| No git identity configured | Leave every file written, skip the commit, and give the user the two `git config` commands. |
| Material is unreadable (private URL, scanned PDF) | Say so, ask the user to paste or export the text, and keep going without it. |
| User wants to stop mid-interview | Write what's gathered, mark empty sections `<!-- TODO -->`, commit, and point at `/<name>:update-context`. |
| User asks to extend an existing kit | Not this skill's job: point at that kit's own `write-skill`, `adopt-skill`, and `update-context`. |
| Name collides with an installed plugin (`name_taken`) | Warn that the slash namespace will clash; suggest a suffixed name (one question). |
