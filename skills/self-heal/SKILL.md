---
name: self-heal
description: Use when asked to self-heal the plugin, pay down its own issue backlog, or turn accumulated skill-improvement suggestions into a PR. Harvests open GitHub issues, scores them on token frugality, code quality, and speed, argues for the top 3, fixes them, and ships one PR.
model: opus
disable-model-invocation: false
argument-hint: "[optional: 'top N', or explicit item ids like '34:3 15:3']"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(gh *), Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Close the loop on this plugin's own backlog: read its open issues, pick the three highest-value improvements, fix them, and ship them as one reviewable PR.

## Items, Not Issues

Issues in this backlog are **batches** — one issue holds 3–4 unrelated suggestions. Every phase of this skill therefore operates on **items**, addressed as `<issue>:<index>` (e.g. `34:3`). Consequences, which the finalize phase depends on:

- A PR never uses `Closes #N` unless *every* item in issue `N` is in it.
- Each item carries its own provenance into its commit message and the PR body.
- An issue is closed only once its last open item is done; otherwise it gets a comment naming what was addressed.

## On Invocation

Print banner (plain text):

```
── bf:self-heal ─────────────────────────────────────────
```

1. `git rev-parse --show-toplevel` — the working tree that will receive the fixes.
2. Resolve the target repo from `origin`. This skill heals the repo it runs in; if `$ARGUMENTS` names a different one, stop and tell the user to run it there.
3. Confirm the tree is clean enough to branch from. If there are uncommitted changes to tracked files, ask once whether to stash them or abort.

## Phase 1 — Harvest

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/self-heal/scripts/harvest-issues.sh" --brief
```

Returns `{repo, counts, items[], notes[]}` with every open item segmented and its body truncated for cheap scoring. Do not re-derive segmentation yourself, and do not fetch full issue bodies at this stage — Phase 3 pulls the full text for selected items only.

If `counts.items` is 0, print "Backlog is empty — nothing to heal." and exit.

## Phase 2 — Score & Select

Score every item on this rubric. The three named criteria are the plugin's stated priorities; the fourth exists because the whole premise is three fixes fitting in one coherent PR.

| Axis | Weight | 0 | 1 | 2 | 3 |
|---|---|---|---|---|---|
| Token frugality | ×3 | no effect | trims occasional output | removes repeated model derivation | moves a per-invocation cost into a script or removes it |
| Code quality | ×2 | cosmetic | clarifies guidance | prevents a recurring class of defect | closes a correctness or data-loss gap |
| Speed | ×2 | no effect | saves a step sometimes | removes a round-trip | removes a whole phase or stall |
| Cost to fix | ×1 | multi-skill redesign | new script + several edits | one file, localized | a few lines in one file |

Most backlog items are workflow or UX suggestions that score near zero on token frugality and speed, so expect flat scores and **apply the tiebreak explicitly** rather than picking arbitrarily:

1. Prefer items whose fix touches files no other selected item touches.
2. Then lower cost to fix.
3. Then the lower issue number (oldest backlog first).

Before scoring, read the files each candidate implicates — a verdict on where something belongs or whether it is already handled is worthless without looking. Drop any item already resolved in the current tree, citing the file and line that satisfies it.

Take the top 3 (or `top N` from `$ARGUMENTS`; if `$ARGUMENTS` names explicit item ids, score only those and skip the ranking).

Write the selection to `<artifact_root>/self-heal/<YYYY-MM-DD>-selection.md` (artifact root per **Generated Artifacts** in `plugin-main.md`): the scored table, the three chosen items with per-item argumentation, the files each will touch, and the items rejected with one line each on why.

Print the argumentation, then ask (one question only):

> Fix these three? Reply `yes`, a different set of ids, or `no`.

## Phase 3 — Fix

Pull the full text of the selected items:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/self-heal/scripts/harvest-issues.sh" --item <id> [--item <id>]...
```

Item ids are **positional** — `34:3` is the third segment of issue 34's body *as it reads now*. Before touching anything, cross-check each fetched item's `title` against the title recorded in the selection artifact. On any mismatch the issue was edited since scoring: stop and re-run Phase 1 rather than fixing whatever now sits at that index.

Create one branch for all three: `chore/self-heal-<YYYY-MM-DD>`.

Apply the `dev` convention (3-step lookup in `plugin-main.md`) and the engineering guidelines throughout. Then, **one item at a time**:

1. Implement the item's ask — the narrowest change that satisfies it. Do not fold in adjacent improvements; unselected items stay in the backlog.
2. Verify it (Phase 4) before moving on.
3. Commit that item alone, following the `git` convention (same lookup): `<type>(#<issue>): <what changed>`, with a body line `Addresses #<issue> item <index>: <item title>`.

Fixes run **sequentially by default** — Parallel Fan-Out in `plugin-main.md` governs uncorrelated *analysis*, not concurrent writers to one tree. Fan out fix agents only if the selected items touch provably disjoint file sets; the moment two overlap, fall back to sequential for all of them.

## Phase 4 — Verify

**This repo has no test suite** — it is prose skills plus bash scripts. Do not borrow a test-running verify phase and do not report green from a command that found nothing to run. Per item:

1. Re-read the edited region and state the item's specific ask alongside the line that now satisfies it. An ask that cannot be quoted back is not done.
2. For an edited `SKILL.md`: run the structural items of the **Review Checklist** in `${CLAUDE_PLUGIN_ROOT}/skills/write-skill/SKILL.md` against it — frontmatter, plugin-main.md first, one-question-per-turn, banner, edge cases. The new-skill items (README row, single-file justification) do not apply when editing an existing skill.
3. For an added or edited script: `bash -n <file>`, then execute it once on real input and confirm the output matches its documented contract. A script whose contract is unexercised counts as unverified.
4. Grep for stale references to anything renamed, removed, or re-scoped — comments and docs that still describe the old behavior are part of the fix, not follow-up.

If an item cannot be verified, revert its commit, return it to the backlog, and say so. Never ship an unverified item to keep the count at three.

## Phase 5 — Finalize

1. **ADR check:** apply **ADR Awareness** from `plugin-main.md` against the changed files before pushing.
2. Push the branch.
3. Open **one** PR via `gh pr create`, titled `chore: self-heal — <n> backlog items`. Body: one section per item giving the source (`#<issue>` item `<index>`), the ask, what changed, and how it was verified. Link every source issue; add `Closes #N` only for an issue whose every item is in this PR.
4. Per source issue, `gh issue comment` naming which items this PR addressed and which remain open. Close an issue only when nothing is left in it.
5. Report the PR url and which items stayed in the backlog.

## Edge Cases & Errors

| Condition | Handling |
|---|---|
| Harvest returns `{"error":...}` | Surface `detail` and stop — `gh_unauthenticated` means `gh auth login`; `no_remote` means pass `owner/repo`. |
| Fewer than 3 items in the backlog | Proceed with what exists; say so rather than padding the set. |
| A selected item's fix targets `skills/self-heal/**` | Flag the self-modification in the argumentation and ask before touching it; never silently rewrite this skill mid-run. |
| An item is already satisfied in the current tree | Drop it in Phase 2 and record it in the selection artifact with the file and line that satisfies it. |
| Two selected items collide in the same file | Sequential fixes only; commit each separately so the PR stays reviewable per item. |
| Branch `chore/self-heal-<YYYY-MM-DD>` already exists | Switch to it and continue — a same-day re-run after a verify failure resumes on the same branch rather than forking a second one. |
| An item is too vague to act on | Leave it in the backlog and record why in the selection artifact — do not guess at an ask. |
| Verify fails after 2 attempts on one item | Revert that item, keep the others, and report it as returned to the backlog. |

Here is the request:
$ARGUMENTS
