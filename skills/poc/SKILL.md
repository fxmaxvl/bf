---
name: poc
description: Use when the user wants to build a proof of concept, prototype, or spike fast — "make a quick POC of…", "prototype this idea", "spike X". Interviews for every nuance, brainstorms the approach, checks the brief is coherent, builds the smallest working version under dev conventions, smoke-runs it, and checks code and brief stay in sync. No git. Every decision lands in a BRIEF.md with an ADR log, so the POC can later serve as proof for a full feature.
model: opus
disable-model-invocation: false
argument-hint: "[idea to prove]"
allowed-tools: Read, Write, Edit, Glob, Grep, Agent, Bash
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Build a working proof of concept of an idea as fast as possible, with every decision recorded in a brief that can seed a real PRD or ADR set later.

**Hard rule — no git.** Never run `git init`, commit, branch, stash, push, or open a PR, and never create or edit a `.gitignore`, in either POC location — the one exception is a throwaway fixture repo inside `poc_dir` when the demo itself needs one. The plugin-main **ADR Awareness** section does not apply: it fires on commit/push/PR, which this skill never reaches. Reading repo state (e.g. `git rev-parse`) to understand the surroundings is fine.

**Hard rule — the brief is a durable record.** `BRIEF.md` is project-facing, so **Durable Record Phrasing** from plugin-main governs all of it. Write plain engineering rationale. Never write "the check flagged…", agent names, phase names, or gate verdicts. A fix a review caused is recorded as the decision or shortcut it amounts to.

Phase flow: `locate → interview → brief check → build → smoke → sync check → wrap-up`.

## On Invocation

Print banner (plain text):

── bf:poc ──────────────────────────────────────────────

1. Read `guidelines.md` via the plugin-main 3-step Convention Lookup.
2. If `$ARGUMENTS` is empty, ask one question — "What idea should the POC prove?" — and use the answer as the idea. Otherwise use `$ARGUMENTS` verbatim.
3. Ask one question: where should the POC live?
   - **Current directory** → `./<slug>-poc/`. It can reuse nearby code. This location is a named exception to the plugin-main `.bf/` rule, because the POC is a deliverable people run and share.
   - **Standalone scratch** → `~/.bf/pocs/<slug>/`, isolated from any project.
4. Resolve and create the directory in one call:
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/poc-paths.sh" --idea "<idea>" --where cwd|scratch
   ```
   It returns `{slug, poc_dir, brief_path, collided}`. If `collided` is true, say in one line that the directory was suffixed. Use these paths as given and do not re-derive them.

## Phase 1 — Interview & Brainstorm

Banner: `── poc | Interview ─────────────────────────────`

Ask **one question per turn**. Where an answer has a sensible default, offer it as the recommended option. Skip any item the idea or an earlier answer already settles. Work from the tightest constraint outward:

1. **Hypothesis** — the one thing this POC must prove, or disprove.
2. **Proof** — the concrete demo or observable result that counts as proven, and who will look at it.
3. **Core flow** — the single path the demo walks, step by step.
4. **Scope** — what is explicitly out, including tempting extras.
5. **Real vs faked** — for every data source, integration, auth step, and piece of infra: real, mocked, or hard-coded.
6. **Stack** — language, framework, and runtime. If nearby code exists (current-directory location), prefer its stack.
7. **Constraints** — time box, must-use or must-avoid tech, and environments it has to run in.
8. **Path to production** — if this proves out, what the full version would need to change.

**Brainstorm, don't just collect.** When the approach, architecture, or stack is still open after the relevant question, propose 2–3 concrete options with one-line trade-offs and recommend one. The user picks. Each pick becomes an ADR entry.

**Write as you go.** After every answer, update `brief_path` using the template below, so a dropped session loses nothing. Stop interviewing when every item is settled or explicitly marked as an open question.

If the user cancels, leave `poc_dir` and the partial brief in place, say where they are, and exit.

### BRIEF.md template

```markdown
# <Idea> — POC Brief

## Hypothesis
## Proof of success
## Core flow
## Scope
### In
### Out
## Real vs faked
| Part | Real / Mocked / Hard-coded | Note |
## Stack
## Constraints
## Decisions
### ADR-<NN>: <title>
- **Context:** …
- **Options:** …
- **Choice:** …
- **Why:** …
## Shortcuts & hardening for production
## How to run
## Open questions
## Path to production
```

The **Shortcuts** section must always contain "No automated tests — verified by a smoke run only", plus every mock and hard-code from **Real vs faked**.

## Phase 2 — Brief Check

Banner: `── poc | Brief check ───────────────────────────`

Spawn one agent, `name: poc-brief-check`, `model: sonnet`. Pass it `brief_path` only, not the contents. Instruct it to read the brief and check that the sections agree:

- the proof actually demonstrates the hypothesis;
- the core flow fits inside the scope and uses only the stack and real/faked parts that are listed;
- every decision is consistent with the constraints and with every other decision;
- nothing is both in and out of scope.

It must return exactly `VERDICT: PASS` or `VERDICT: ISSUES` followed by at most 7 one-line issues, each naming the two sections that conflict.

On ISSUES, fix the ones the brief already answers. For any issue that needs a decision, ask the user, one question per turn. Re-run the check at most once. Anything still unresolved after that goes into **Open questions**.

## Phase 3 — Build

Banner: `── poc | Build ─────────────────────────────────`

1. Resolve `dev.md` via Convention Lookup, plus the language convention (`typescript` or `python`) when it matches the stack. Apply them, but at POC scale: favour the smallest code that proves the hypothesis, and skip anything that serves only production.
2. Build only the core flow, using the real, mocked, and hard-coded split exactly as the brief records it. Keep all files inside `poc_dir`.
3. Any non-trivial choice made while building (a library, a data shape, a workaround) gets an ADR entry in the brief at the moment it is made. Every new shortcut is added to **Shortcuts**.
4. If the stack's tooling is missing (runtime, package manager), ask the user one question: install it, or switch the stack. Record the answer as an ADR entry.

## Phase 4 — Smoke Run

Banner: `── poc | Smoke ─────────────────────────────────`

Run the core flow end to end once and observe the proof from the brief. Write the exact commands under **How to run**. If the run fails, fix it and retry, up to 3 attempts in total. If it still fails, record the failure and its last error under **Open questions**, tell the user, and continue to the sync check anyway.

## Phase 5 — Sync Check

Banner: `── poc | Sync check ────────────────────────────`

Spawn one agent, `name: poc-sync-check`, `model: sonnet`. Pass it `poc_dir` and `brief_path`. Instruct it to read both and report drift between them:

- tech or libraries in the code that no ADR entry or **Stack** covers;
- mocks or hard-codes that are not listed in **Real vs faked** or **Shortcuts**;
- **How to run** that does not match the code's entry point;
- flow steps that are in the brief but not built, or built but not in the brief.

It uses the same verdict format as the brief check. Fix every issue in whichever side is wrong, usually the brief. Re-run at most once.

## Wrap-up

Print a short summary in plain text: `poc_dir`, the one-line hypothesis with whether the smoke run proved it, the count of ADR entries, the run command, and any open questions. Then suggest `/bf:feature` seeded with `brief_path` for when the POC graduates.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `poc-paths.sh` returns an `error` | Show the `detail`, fix the argument, and re-run once. |
| POC directory already exists | The script suffixes `-2`, `-3`, …; note it in one line. |
| The user cancels mid-interview | Keep the partial brief, report its path, exit. No cleanup. |
| An idea needs git (e.g. a git-hook tool) | Use a throwaway fixture repo inside `poc_dir` for the demo only; never touch the enclosing repo. Record this as an ADR entry. |
| Tooling for the chosen stack is missing | Ask one question: install or switch stack. Record it as an ADR entry. |
| Smoke run still failing after 3 attempts | Record it under **Open questions**, tell the user, and continue to the sync check. |
| A check agent returns an unparseable verdict | Treat it as PASS, say so in one line, and move on. Speed beats a second round. |
| The idea is too big to prove in one flow | During the interview, propose narrowing the hypothesis to a single flow and record the narrowing in **Scope → Out**. |
