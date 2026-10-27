---
name: essence
description: "Use when a finished research report, PRD or spec has too much in it and you want only what matters — 'cut this down to the essentials', 'what actually matters in this PRD', 'reduce the noise in this research', 'give me the vital few'. One pass in the spirit of McKeown's Essentialism: locks one essential intent with you, keeps at most N vital directions (default 3), carries hard constraints through untouched, and parks everything else with a reason. Writes a distilled copy; the original is never edited. Not for multi-session requirements work (bf:gather), plain summarising, or PRs."
model: opus
disable-model-invocation: false
argument-hint: "[top N] <path to research report, PRD or spec>"
allowed-tools: Read, Write, Edit, Grep, Bash(bash *), Bash(mkdir *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Distill an existing artifact to its essential directions. Most of any document is noise; the work is *choosing*, and every cut stays visible.

**Hard rules.**
- **Propose-only.** Never edit the source. The output is a new file.
- **Nothing is lost silently.** Every candidate lands in exactly one bucket — `vital`, `non_negotiable`, `parked` (with a reason) or `merged` (into a vital one). `ledger-check.sh` enforces the accounting.
- **Never invent.** Kept directions stay in the document's own words. No new directions, facts or requirements.
- **One pass.** Lock the intent once, cut once. Do not re-open settled cuts on later turns.

## On Invocation

Print the banner as plain text: `── bf:essence ─────────────────────────────────────────`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/essence/scripts/essence-init.sh" $ARGUMENTS
```

On `{"error":…}` print `detail` and stop (`pr_deferred` → point to `/bf:walkthrough`; `already_distilled` → ask for the source doc instead). Otherwise keep `source`, `budget`, `out_path` and `ledger_path`.

## Phase 1 — Explore: extract candidates

Read `source` in full. List every **candidate**: each distinct direction, requirement, finding, recommendation or open question. Not each paragraph — one claim per candidate. For each, record `id` (`C1`, `C2`, …), `claim` (one line, the doc's wording) and `locator` (the heading it sits under).

Mark a candidate **non-negotiable** only when the document itself states it as a hard constraint: a MUST, a compliance, security, legal or contractual requirement, or an explicitly fixed limit. Its locator is the evidence. Do not promote anything to non-negotiable on your own judgment.

Draft the **essential intent**: one sentence naming the single outcome the document serves, ending in an observable *done when …*. Take it from the doc's stated goal, TL;DR or problem statement. If the doc states none, derive it from the candidates and say that you did.

## Phase 2 — Lock the intent (the one question)

Present, then ask one question and wait:

> **Essential intent:** <sentence — done when …> *(from: <locator> | derived)*
> **Non-negotiables carried through regardless of score:** <list with locators, or "none stated">
> **Budget:** <budget> vital directions
>
> Is this the intent to cut against? Accept it, or tell me what to change.

This is the skill's only question. Apply the answer, then do not re-ask.

## Phase 3 — Eliminate

1. **Score** every candidate except the non-negotiables 0–100 on how much it moves the intent. The score explains every cut; rank decides it.
2. **Keep** the highest-ranked as `vital`, at most `budget`. The budget is a ceiling, not a target: below 90 is not a clear yes, so when fewer than `budget` candidates score 90+, keep only those.
3. **Condense.** A candidate that restates a vital one becomes `merged` with `into: <vital id>`, and the vital entry lists it in `absorbs`. Merge only when every claim of the merged candidate survives in the vital one's wording. Otherwise it stays a separate candidate.
4. **Park** everything else with a one-line `reason` tied to the intent ("serves onboarding, not the intent"), never "low priority".

Write the ledger (`{budget, intent, candidates:[…]}`) to `ledger_path`, then:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/essence/scripts/ledger-check.sh" "<ledger_path>"
```

Fix every `errors` entry and re-run, up to 3 attempts. If it still fails, print the errors and stop without writing the output. The script checks accounting only. Checking that each absorbed claim really survives in its target's wording is yours.

## Phase 4 — Edit: write the distilled copy

McKeown's edit is cut, condense, correct, and restraint:
- **Cut:** only parked candidates leave the body.
- **Condense:** fold merged wording into its vital direction.
- **Correct:** *flag* tensions — a kept item that contradicts another or the intent. Never rewrite a direction to resolve one.
- **Restraint:** keep the doc's words. Do not polish, expand or add.

Write `out_path`:

```markdown
<!-- bf:essence source=<source> budget=<budget> -->
# Essence: <source document title>

**Source:** <source> · **Date:** <YYYY-MM-DD> · **Kept:** <vital> of <total> (+<non_negotiable> non-negotiable)

## Essential intent
> <sentence — done when …>

## The vital few
### 1. <direction, short>
<the direction in the doc's words, condensed> *(from: <locator>; absorbs: <ids or —>)*

## Non-negotiables
- <claim> *(from: <locator>)*

## Tensions
- <C_a> vs <C_b>: <the contradiction, one line>   ← omit the section when there are none

## Parked
| Item | From | Why it's out |
|------|------|--------------|
| <claim> | <locator> | <reason> |
```

## Phase 5 — Report

Print `out_path`, the essential intent, the vital few (titles only) and the counts line. Then offer one next step that fits the source: `/bf:feature` or `/bf:design` to build from it, `/bf:gather` for a PRD that still has open questions.

If the user wants a parked item back, **swap** it with a vital one so the budget holds. Update the ledger, re-run `ledger-check.sh`, rewrite the output. A swap is not a re-cut.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Fewer candidates than the budget | Keep the ones that serve the intent; say nothing needed cutting. Still write the output. |
| Every candidate is non-negotiable | Write the output with an empty vital few and say the doc is all constraints, so there is nothing to cut. |
| Doc states no goal | Derive the intent and mark it *(derived)* in Phase 2. |
| User's answer rewrites the intent | Use their wording verbatim; no second confirmation. |
| User asks for a full re-cut | Refuse once, briefly: one pass per artifact. Offer a swap, or a new run with a different `top N`. |
| Source is very large (thousands of lines) | Extract per top-level section, then dedupe candidates across sections before scoring. |
