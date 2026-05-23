---
name: consistency-gate
description: Use when you need to verify that changes, a design, or a plan are internally consistent — naming, style, comments, references, effectiveness, and goal alignment — across a git diff, spec block, or plan block. Invoked as a gate inside bf flows (review-design, plan, verify) and usable standalone.
model: opus
disable-model-invocation: true
argument-hint: "[optional: path/block to check — omit when called from a bf flow]"
allowed-tools: Read, Grep, Glob, Bash(git *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Consistency gate — evaluates a target artifact for internal and contextual consistency across six lenses: naming, style, comments/docs, references, effectiveness, and goal alignment. Produces a structured STATUS report. The caller decides whether to surface it.

## Mode Detection

Run state-ops.sh to check for an active session:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" 2>/dev/null
```

| Condition | Mode | Input |
|-----------|------|-------|
| `phase = review-design` | Spec advisory | `paths.spec` block |
| `phase = plan` | Plan advisory | `paths.plan` block |
| `phase = verify` | Code scan | `changed_files` from `changed-packages.sh` |
| No active session / `$ARGUMENTS` provided | Standalone | `$ARGUMENTS` (path, block reference, or pasted text) |

For `verify` mode also run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/changed-packages.sh"
```

---

## Lenses (applied in every mode)

For each finding, record which lens triggered it.

| Lens | What to check |
|------|---------------|
| **Naming** | Identifiers, variables, functions, files follow the conventions of surrounding code; concepts are named consistently across the artifact |
| **Style** | Formatting, structure, and conventions match the surrounding codebase; no gratuitous divergence |
| **Comments & docs** | Comments are accurate and match the current code/design; stale, misleading, or absent-where-needed docs are flagged |
| **References** | Imports, cross-references, citations, and links resolve and point to what is actually used; no phantom or orphaned references |
| **Effectiveness** | The change/design actually accomplishes its stated goal; no obvious gaps between intent and implementation |
| **Goal alignment** | The artifact serves the reason the surrounding code/section exists; no drift from the module's/component's purpose |

---

## Spec Advisory Mode (`phase = review-design`)

Extract the `## Spec` block from `paths.spec` using the Block Reading Pattern from `plugin-main.md`. Apply all six lenses to the proposed design — before any code is written.

Focus on:
- Concept names used in the spec that differ from existing codebase terminology (Naming)
- Sections that propose behavior at odds with the stated goal of the component (Goal alignment)
- References to modules, APIs, or abstractions that do not yet exist or are named differently (References)
- Design decisions whose described outcome does not logically follow from the approach (Effectiveness)

All findings are `ADVISORY`. STATUS: `PASS` or `ADVISORY`.

---

## Plan Advisory Mode (`phase = plan`)

Extract the `## Plan` block from `paths.plan` using the Block Reading Pattern from `plugin-main.md`. Apply all six lenses to the implementation steps — before code is written.

Focus on:
- Step descriptions that use names inconsistent with the spec or existing codebase (Naming)
- Steps that would produce an outcome that doesn't match the accepted spec/design (Goal alignment)
- Steps referencing files, functions, or APIs that don't exist under those names (References)
- Steps whose stated outcome cannot follow from the stated action (Effectiveness)

All findings are `ADVISORY`. STATUS: `PASS` or `ADVISORY`.

---

## Code Scan Mode (`phase = verify`)

**Doc-only short-circuit:** If every entry in `changed_files` matches `\.(md|mdx|txt|rst)$`, emit `STATUS: PASS` with a single note line `Skipped: doc-only changes` and stop. Write nothing else to the report. (The regex is deliberately conservative — extensions only; files like `LICENSE` or `CHANGELOG` without an extension are not matched and proceed through normal scanning.)

Scan `changed_files` using Grep and Read. Apply all six lenses to actual code changes and their surrounding context.

Focus on:
- New identifiers that clash with existing names for the same concept, or duplicate existing names for a different concept (Naming)
- Changed files whose style departs from the conventions of files they touch (Style)
- New or modified comments that no longer match the code they annotate (Comments)
- Imports or references added but not used, or used but not imported (References)
- Changes that don't reach the call site or data path they intended to fix (Effectiveness)
- Changes whose logic serves a different purpose than the module was built for (Goal alignment)

### Severity

- **BLOCK** — finding in a file listed in `changed_files` (introduced this session)
- **ADVISORY** — finding in a file outside `changed_files` (pre-existing or peripheral)
- **PASS** — no findings

Overall STATUS escalates: `PASS` → `ADVISORY` → `BLOCK`.

---

## Standalone Mode

When no active session is found, read `$ARGUMENTS` as the target:
- If it is a file path: read the file.
- If it is a `paths.*` reference: resolve via the session log if one exists at `$(git rev-parse --show-toplevel)/.bf/sessions/` (most recent `*-session-log.md`).
- If it is pasted text: treat it as the artifact directly.

Apply all six lenses. STATUS follows the code-scan severity rules (BLOCK/ADVISORY/PASS) based on whether findings touch the explicit target.

---

## Report Format

Write the report to `paths.consistency_report` (= `paths.temp`) using `## Consistency Report` as the block header (Block Writing Pattern from `plugin-main.md`). In standalone mode: print to conversation only, do not write to file.

No findings:

```markdown
## Consistency Report

STATUS: PASS
```

Findings present:

```markdown
## Consistency Report

STATUS: BLOCK | ADVISORY

### BLOCK — must resolve before proceeding

- `<file>:<line or spec section>` — **<Lens>** — <what was observed> — **Fix:** <concrete correction>

### ADVISORY — inconsistency detected (pre-existing or design risk)

- `<file>:<line or spec section>` — **<Lens>** — <what was observed> — **Suggestion:** <concrete correction>
```

Omit sections with no entries.

Do **not** modify any source files. Do **not** ask the user questions. The caller handles gate logic.

---

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| No active session and no `$ARGUMENTS` | Print: "consistency-gate: no target. Pass a file path, block reference, or text as an argument." Then stop. |
| `changed_files` is empty in verify mode | STATUS: PASS with note "No changed files detected." |
| Target artifact is empty or unreadable | STATUS: ADVISORY with note "Target could not be read: `<path>`." |
| Standalone target is pasted text with no codebase context | Apply Naming, Effectiveness, Goal alignment lenses only; note the other lenses were skipped (no surrounding code). |
