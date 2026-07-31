---
name: adr-writer
description: Use when the user wants to document an architecture decision, write an ADR, create a decision record, or amend/update/supersede an existing ADR. Interactively gathers the context, options considered, and chosen approach, then drafts or amends a numbered Architecture Decision Record that cites only tracked source files.
model: sonnet
disable-model-invocation: false
argument-hint: "[decision title, e.g. 'use Postgres for the events table'] | AMEND: [ADR number or path]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(mkdir *), Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules, including the **one-question-per-turn** rule that applies at every interactive point in this skill.

Produce a numbered Architecture Decision Record (ADR) via interactive Q&A, saved as a real project doc (not a `.bf/` session artifact).

## On Invocation

Run: `git rev-parse --show-toplevel`

If this fails, print: "Not a git repository. ADRs need a repo to resolve a doc location against. Exiting." and stop.

Print banner (plain text):

```
── bf:adr-writer ────────────────────────────────────────
```

### Mode detection

- If `$ARGUMENTS` starts with `AMEND:` (case-insensitive, leading whitespace tolerated) → **amend mode**. Continue at "## Amend Track" below. The text after the marker is an optional selector: a 4-digit ADR number (`0003`), a bare filename (`0003-use-postgres.md`), or a repo-relative path. Empty remainder → the Amend Track's picker step handles it.
- Anything else, including empty `$ARGUMENTS` → **create mode**. Continue at "## Phase 1 — Gather" below, unchanged.
- Never infer amend mode from free text (e.g. "update the ADR about X"). If a selector doesn't resolve to exactly one existing ADR, fall back to the picker — do not guess.

## Phase 1 — Gather

Ask ONE question at a time, waiting for each answer before asking the next:

1. **Title** — what decision is this? (Use `$ARGUMENTS` as the title if non-empty; otherwise ask.)
2. **Context** — what problem or constraint forced this decision?
3. **Options considered** — what alternatives were on the table, and why were they passed over?
4. **Decision** — which option was chosen?
5. **Consequences** — what trade-offs, follow-up work, or risks does this decision create?
6. **(Optional) Affected code** — any specific files, modules, or components this decision touches? Skip if the user has nothing specific in mind.

## Amend Track (amend mode)

Entered instead of Phase 1 when Mode detection selects amend mode. Reuses the create flow's verification and content rules rather than duplicating them.

1. Run (same command as Phase 2):

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/resolve-adr.sh"
   ```

   Use the `adrs` array from its output for the picker below.

2. If `adrs` is empty: tell the user there are no existing ADRs to amend and ask one question — "No existing ADRs found. Create a new one instead?"
   - **Yes** — strip the `AMEND:` marker and any selector text from `$ARGUMENTS` first, then ask a fresh one-question title prompt. Do **not** pass the raw `$ARGUMENTS` (e.g. the literal string `"AMEND: 0003"`) through as the title. Continue at Phase 1, step 2 (Context), using the fresh title as the answer to step 1.
   - **No** — stop.
3. If a selector was supplied after the `AMEND:` marker and it matches exactly one entry in `adrs` (by number, filename, or path), skip the picker and use that entry. Otherwise, present the numbered `NNNN — Title` list (mirroring the Pick Mode pattern in `skills/gh/SKILL.md`) and ask one question: "Which ADR do you want to amend?"
4. Read the selected ADR file in full.
5. Gather the amendment via one-question-at-a-time Q&A:
   - What changed?
   - Why now?
   - Does this amendment extend, narrow, or supersede the recorded decision?
6. Apply the amendment **in place to the existing numbered file** — same number, same filename, no renumbering, no new file.
   - For any newly referenced files, reuse Phase 3's tracked-file verification (`git ls-files --error-unmatch`).
   - The **Content rules** block in Phase 4 (no Claude/skill/tool/agent mentions, no meta-commentary, no internal spec-IDs or process mechanics, tracked source files only) applies unchanged — do not restate or fork it.
7. Route into Phase 5 — Review (accept / revise) rather than adding a second review loop.

## Phase 2 — Resolve path

Run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-adr.sh"
```

This returns JSON: `{"adr_dir": "...", "dir_exists": bool, "next_number": "NNNN", "adrs": [{"number": "NNNN", "title": "...", "path": "..."}]}`.

Derive a slug from the title: kebab-case, ASCII only, strip filler words (a, an, the, of, to, in, for, on, at, by, with, and, or, but), cap at 40 characters at a word boundary.

Output path: `<adr_dir>/<next_number>-<slug>.md`

If `dir_exists` is false, create it with `mkdir -p "<adr_dir>"` before writing.

## Phase 3 — Verify referenced files

For each file/component mentioned in step 6 of Phase 1, confirm it's a **tracked source file**, not a temp, untracked, or generated artifact:

```bash
git ls-files --error-unmatch -- <path>
```

- If tracked: include it in the ADR by its repo-relative path.
- If untracked, under `.bf/`, `.git/`, a build directory, or otherwise not a real committed source path: drop it from the ADR body and mention to the user (inline, not in the doc) that it was excluded because it isn't a tracked source file.

## Phase 4 — Draft

Write the ADR to the resolved path using this template:

```markdown
# <NNNN>. <Title>

## Status

Accepted

## Context

<context from Phase 1, step 2>

## Decision

<decision from Phase 1, step 4>

## Considered Options

- **<Option>** — <why it was passed over>
  (repeat per option from Phase 1, step 3)

## Consequences

<consequences from Phase 1, step 5>

## Related Code

- `<path>` — <one-line note>
  (only tracked paths verified in Phase 3; omit this section entirely if none)
```

**Content rules — enforce strictly:**

- Reference **only tracked source files** verified in Phase 3. Never cite paths under `.bf/`, `.git/`, session logs, scratch/temp files, or anything `git ls-files` doesn't recognize.
- The document is a project artifact, not a transcript. Do **not** mention Claude, an AI assistant, this skill, `/bf:adr-writer`, or how the document was produced. Write it exactly as a human author would.
- No meta-commentary ("Generated by...", "via bf:adr-writer", authoring tool credits, timestreamed process notes).
- No internal spec-ID references (e.g. "FR-7") or agent/critic names and internal process mechanics (e.g. "consilium", "critic", "lenses"). Write the rationale as plain engineering prose fit for a durable record — cite the convention rule, code path, or trade-off directly.

## Phase 5 — Review

Show the user the absolute path and the rendered content. Ask one question:

> Accept as-is, or revise?

- **Accept** — print the absolute path and end.
- **Revise** — ask one question: "What would you like to change?" Apply the edit, then return to the top of this phase.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Not a git repository | Stop at invocation — ADRs need a resolvable repo-relative path. |
| No existing ADR directory found | Default to `docs/adr/`, starting at `0001`. |
| Referenced file is untracked or doesn't exist | Exclude it from the doc; tell the user why, inline in conversation. |
| Filename collision at the resolved path | Re-run `resolve-adr.sh` conceptually by incrementing the number by one; this should not happen since the script scans existing files, but guard against races. |
| User has no options to list (obvious/forced decision) | Allow "no alternatives considered" as the answer; omit the Considered Options section. |
| Amend mode: no existing ADRs found (`adrs` is empty) | Offer to create one instead — one question; on yes, strip the `AMEND:` marker/selector before asking a fresh title. |
| Amend mode: `AMEND:` selector matches zero or multiple ADRs | Fall back to the picker rather than guessing; show the numbered list and ask which one. |
| Amend mode: selected ADR file has no parsable `# ` title | Read the file body anyway; refer to it by its filename/number in conversation. |
| Amend mode: the amendment contradicts (rather than extends/narrows) the recorded decision | Surface this to the user and ask whether a new superseding ADR is the better move instead of editing in place. |
