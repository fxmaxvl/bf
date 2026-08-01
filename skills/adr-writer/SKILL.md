---
name: adr-writer
description: Use when the user wants to document an architecture decision, write an ADR, create a decision record, or amend/update an existing ADR. Interactively gathers the context, options considered, and chosen approach, then drafts or amends a numbered Architecture Decision Record that cites only tracked source files. Superseding a decision is a manual two-step (run create mode for the successor decision first, then amend the predecessor ADR's Status once the new path is known) — not a single mode.
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

- If `$ARGUMENTS` starts with `AMEND:` (case-insensitive, leading whitespace tolerated), let `remainder` be the text after the marker, trimmed:
  - **Unambiguous selector** — `remainder` is empty, OR is a bare 1–4 digit number, OR matches an ADR-filename shape: `<NNNN>-<slug>.md` or `<repo-relative-path>/<NNNN>-<slug>.md` (i.e. the basename **starts with** 4 digits followed by `-` and ends in `.md`, optionally preceded by a path — the exact form `resolve-adr.sh` emits as `adrs[].path`, e.g. `docs/adr/0003-postgres.md`) → **amend mode (unambiguous)**. Set `selector` to `remainder` (possibly empty) and `title_hint` to empty. Continue at "## Amend Track" below.
  - **Everything else** (free text not matching that shape — e.g. `AMEND: CI/CD pipeline ownership`, or a create-mode title that merely ends in `.md` like `AMEND: deprecate README.md` or `AMEND: retire plan-2024.md`) → **amend mode (candidate)**. This remainder has not been shown to be a real selector yet — it might resolve to an ADR, or it might be an ordinary title that happens to start with the marker. Set `selector` to `remainder` and `title_hint` to the full, unmodified `$ARGUMENTS` (marker included — it doubles as the fallback title if resolution fails). Continue at "## Amend Track" below; resolution happens there once `adrs` is available (step 3): a confirming question is asked before falling back to create mode on a zero-match (see Amend Track step 3).
- Anything else, including empty `$ARGUMENTS` → **create mode**. Set `title_hint` to the full, unmodified `$ARGUMENTS`. Continue at "## Phase 1 — Gather" below, unchanged.
- Never infer amend mode from free text elsewhere in the string.

## Phase 1 — Gather

Ask ONE question at a time, waiting for each answer before asking the next:

1. **Title** — what decision is this? (Use `title_hint` as the title if non-empty; otherwise ask.)
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

2. Determine how many entries in `adrs` the `selector` (from Mode detection) matches — zero, one, or multiple — by number (compare zero-padded to 4 digits, so `3` matches `0003`), filename, or path.
3. Branch on which form of amend mode Mode detection selected:
   - **Unambiguous** (`title_hint` is empty): if `adrs` is empty, tell the user there are no existing ADRs to amend and ask one question — "No existing ADRs found. Create a new one instead?"
     - **Yes** — enter Phase 1 at step 1; `title_hint` is empty, so it will ask for a title.
     - **No** — stop.
     Otherwise, if `selector` is non-empty and matches exactly one entry, use that entry. If `selector` is empty, or matches zero or multiple entries, present a numbered list, one `NNNN — Title` per line, and ask one question: "Which ADR do you want to amend?"
   - **Candidate** (`title_hint` is non-empty): if `selector` matches exactly one entry, use that entry and discard `title_hint` — this is now amend mode. If it matches **multiple** entries, present the same numbered `NNNN — Title` list as the unambiguous path and ask "Which ADR do you want to amend?" — do not offer to create a new one when ADRs plausibly match. If it matches **zero** entries (including when `adrs` is empty), ask one confirming question: "No ADR matches `<selector>`. Create a new ADR titled `<title_hint>` instead?"
     - **Yes** — abandon amend mode, enter Phase 1 at step 1 using `title_hint` as the title.
     - **No** — stop.
4. Read the selected ADR file in full.
5. Gather the amendment via one-question-at-a-time Q&A:
   - What changed?
   - Why now?
   - Does this amendment extend or narrow the recorded decision? (Superseding a decision isn't an in-place amendment — see the Edge Cases row below.)
6. Apply the amendment **in place to the existing numbered file** — same number, same filename, no renumbering, no new file.
   - For any newly referenced files **cited in the ADR body** (Related Code / Context — the files gathered in Phase 1 step 6), reuse Phase 3's tracked-file verification (`git ls-files --error-unmatch`). This bullet does **not** govern the `## Status` line's supersede target — see the next bullet.
   - The **Content rules** block in Phase 4 applies unchanged — do not restate or fork it.
   - `## Status` is an amendable field. Its only two permitted values are `Accepted` (the Phase 4 template default) and `Superseded by <repo-relative path>` (set once a successor ADR exists — see the Edge Cases row on superseding below for the required order). The `Superseded by <path>` value is validated by **file existence at the resolved path** (the successor ADR was created in the preceding create-mode run of the two-step, so it exists on disk but is not yet committed — confirm with `Read` or `Glob`, both of which are permitted) — not by `git ls-files`. It is a sibling decision document, not an external source-file citation, so the tracked-file-verification bullet above does not apply to it.
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
- Durable-record rationale must follow the Durable Record Phrasing rule in `plugin-main.md`.

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
| `$ARGUMENTS` is a create-mode title that legitimately begins `Amend:` (e.g. `AMEND: CI/CD pipeline ownership`, `Amend: retention policy for event logs`, `AMEND: deprecate README.md`) | Mode detection does not discard the title on a free-text remainder. Any remainder that isn't a bare 1–4 digit number and doesn't match the ADR-filename shape (`<NNNN>-<slug>.md`, optionally path-prefixed) enters amend mode as a *candidate*, with `title_hint` kept as the full `$ARGUMENTS` — this includes remainders that merely end in `.md` without a 4-digit prefix. If the candidate resolves to zero ADRs, the confirming question below is asked; on yes, Phase 1 proceeds with `title_hint` verbatim as the title (marker included). If it resolves to multiple, the numbered picker is shown instead (see below) — no title is lost either way. |
| Amend mode (unambiguous form — bare digits or a remainder matching the ADR-filename shape): no existing ADRs found (`adrs` is empty) | Offer to create one instead — one question; on yes, enter Phase 1 at step 1 (`title_hint` is empty, so it asks). |
| Amend mode (unambiguous form): selector matches zero or multiple ADRs | Fall back to the picker rather than guessing; show the numbered list and ask which one. |
| Amend mode (candidate form — free-text remainder not matching the ADR-filename shape): selector matches multiple ADRs | Present the same numbered `NNNN — Title` list as the unambiguous path and ask which one — do not offer to create a new ADR when entries plausibly match. |
| Amend mode (candidate form): selector matches zero ADRs | Ask one confirming question: "No ADR matches `<selector>`. Create a new ADR titled `<title_hint>` instead?" **Yes** — proceed to create mode with that title. **No** — stop. No numbered picker is shown (nothing matched), but the mode switch itself is never silent. |
| Amend mode: selected ADR file has no parsable `# ` title | Read the file body anyway; refer to it by its filename/number in conversation. |
| Amend mode: the amendment contradicts, or should supersede rather than extend/narrow, the recorded decision | Surface this to the user. Superseding is a manual two-step, not a mode of this skill: (1) run create mode for the successor decision first, deriving its path; then (2) amend the predecessor ADR's `## Status` to `Superseded by <path of the new ADR>` using that path. |
