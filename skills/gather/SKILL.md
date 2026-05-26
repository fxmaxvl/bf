---
name: gather
description: Use when you have a PRD, product brief, or research doc that needs iterative requirements distillation across multiple sessions. Tracks open questions and blockers, versions the output doc as understanding evolves, scopes a minimal POC slice, and produces a versioned source-of-truth doc that feeds into bf:feature or bf:design.
model: opus
disable-model-invocation: false
argument-hint: "[feature name or path to PRD]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(find *), Bash(ls *), Bash(mkdir *), Bash(cat *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Orchestrate an iterative requirements-gathering loop across one or more sessions. Each session reads the current state (open questions, known requirements, decisions made), converses with the user to close questions or surface new ones, and writes an updated versioned output doc. Sessions can be interrupted and resumed freely.

**Hard rule — one question per turn:** ask exactly one question, then stop and wait. Never batch questions.

**Hard rule — always write state before ending:** every session must flush state to disk before exiting, even if the user cancels mid-way.

## State Layout

State lives in one of two places (first match wins):

```
<project_root>/.bf/gather/<feature-slug>/   ← preferred when inside a git repo
~/.bf/gather/<feature-slug>/                ← fallback when no git repo detected
```

Inside that directory:

| File | Purpose |
|------|---------|
| `state.json` | Open questions, resolved questions, decisions, current version counter |
| `prd-source.md` | The original PRD/brief as provided (copied in on first session) |
| `v<N>-requirements.md` | Versioned output doc; N increments when a significant update is flushed |

Compute `<project_root>` with:
```bash
git rev-parse --show-toplevel 2>/dev/null
```
If that fails, use `~/.bf/gather/`.

## state.json Schema

```json
{
  "feature": "<slug>",
  "version": 1,
  "status": "in_progress | poc_scoped | complete",
  "prd_source": "<absolute path to prd-source.md>",
  "open_questions": [
    { "id": "q1", "text": "...", "status": "open | resolved | blocked", "resolution": "" }
  ],
  "decisions": [
    { "id": "d1", "text": "...", "rationale": "..." }
  ],
  "poc_scope": "",
  "full_scope_summary": "",
  "session_count": 1,
  "last_session": "<ISO date>"
}
```

## On Invocation

1. Print banner:
   ```
   ── bf:gather ───────────────────────────────────────────
   ```

2. Detect git root:
   ```bash
   git rev-parse --show-toplevel 2>/dev/null
   ```
   Set `GATHER_ROOT` to `<git_root>/.bf/gather` or `~/.bf/gather` as appropriate.

3. If `$ARGUMENTS` is a feature slug or name: derive slug (kebab-case, ASCII, max 40 chars).
   If `$ARGUMENTS` is empty: proceed to Phase 1 — the skill will ask for the feature name.

4. Check whether `$GATHER_ROOT/<slug>/state.json` exists:
   - **Exists** → Phase 2 (Resume).
   - **Does not exist** → Phase 1 (New session).

## Phase 1 — New Session

Print banner: `── bf:gather | New ─────────────────────────────────────`

Ask (one question at a time, wait for each answer):

1. If no slug yet: "What is this feature called?" — derive slug from answer.
2. "Do you have a PRD, brief, or research doc from product? If yes, paste it or give me the file path. If not, describe the feature in a few sentences."

On answer:
- If a file path is given: Read it.
- If pasted text or description: treat the user's input as the source doc.
- Copy/save the raw source content to `$GATHER_ROOT/<slug>/prd-source.md`.

Then proceed to Phase 3 — Gather.

## Phase 2 — Resume

Print banner: `── bf:gather | Resume ──────────────────────────────────`

Read `$GATHER_ROOT/<slug>/state.json` and the latest `v<N>-requirements.md`.

Show a one-paragraph status summary:
- Feature name, current version, status
- Count of open/resolved/blocked questions
- POC scope (if set)

Ask: "Want to continue where we left off, update the source PRD, or review what we have?"

Branch:
- **Continue** → Phase 3 (Gather) with existing state loaded.
- **Update PRD** → ask for the new PRD content/path, update `prd-source.md`, then Phase 3.
- **Review** → Phase 4 (Review & Output) directly.

## Phase 3 — Gather

Print banner: `── bf:gather | Gather ──────────────────────────────────`

Work through open questions and surface new ones. For each turn:

1. Pick the **highest-priority open question** from `state.json` (or the most important unknown derived from the PRD if no questions exist yet).
2. Ask the user that one question.
3. On answer:
   - Mark the question `resolved` with the resolution text.
   - If the answer reveals new unknowns, add them to `open_questions`.
   - If a decision was made, append it to `decisions`.
4. After each answer, ask: "Anything to add, or shall I ask the next question?"
   - If they want to continue: loop back to step 1.
   - If they say done/stop/enough: proceed to Phase 4.

**Codebase reads:** if a question requires understanding an existing system, read relevant files or grep for symbols before asking — present what you found as context in the question.

**POC scoping:** once the full scope is reasonably understood, ask once: "Want to scope a minimal POC slice now?" If yes, work with the user to define it and save to `poc_scope` in state.

## Phase 4 — Review & Output

Print banner: `── bf:gather | Output ──────────────────────────────────`

1. Generate a new versioned requirements doc at `$GATHER_ROOT/<slug>/v<N>-requirements.md` with this structure:

   ```markdown
   # <Feature Name> — Requirements v<N>

   > Status: <in_progress | poc_scoped | complete>
   > Last updated: <ISO date>
   > Sessions: <count>

   ## Full Scope
   <Summary of the full feature as understood>

   ## POC Scope
   <Minimal slice to implement first, or "Not yet scoped">

   ## Requirements
   <Bullet list of known requirements, grouped logically>

   ## Open Questions
   <Table: ID | Question | Status | Resolution>

   ## Decisions
   <List of decisions made and their rationale>

   ## Source PRD
   > See `prd-source.md` in this directory
   ```

2. Increment `version` in `state.json`, update `last_session` and `session_count`, flush state.

3. Tell the user:
   - Absolute path to the new `v<N>-requirements.md`
   - Count of questions resolved this session / still open
   - POC scope status

4. Ask: "Want to hand off to `/bf:feature` (with this doc as the spec) or `/bf:design` (to produce a system-design doc)?"
   - **bf:feature** → invoke `Skill("bf:feature", args="<feature name>\n\n(Requirements doc: <absolute path>)")`.
   - **bf:design** → invoke `Skill("bf:design", args="<feature name>\n\n(Requirements doc: <absolute path>)")`.
   - **Neither / not yet** → end session, print the absolute path.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| No git repo and `~/.bf/gather/` doesn't exist | Create `~/.bf/gather/<slug>/` with `mkdir -p` |
| User provides a file path that doesn't exist | Warn and re-ask (one question): "That file wasn't found — paste the content directly?" |
| state.json is malformed or missing fields | Warn, show what was parsed, ask if user wants to reset state for this feature |
| User cancels mid-gather | Flush current state to disk anyway before exiting; confirm path written |
| Feature slug collision (different feature, same slug) | Show existing feature summary, ask: "Resume this feature, or start a new one with a different name?" |
| PRD updated mid-session without version bump | Treat as a continuation; only bump version on output phase |
| Handoff to bf:feature / bf:design declined | End cleanly; print the requirements doc path and remind user they can resume with `/bf:gather <feature-name>` |
