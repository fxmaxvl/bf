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

Bodies that use neither `### ` headings nor `- **` bullets cannot be split by pattern, so they arrive as one item. With TypeSafe boosting on (`/bf:typesafe`), `boost-segments.py` re-splits exactly those at judged item boundaries and caches the result by body digest, so a later `--item` run slices where this one did. Without it the single-item fallback stands — say so in Phase 2 rather than pretending a lump is one suggestion.

If `counts.items` is 0, print "Backlog is empty — nothing to heal." and exit.

## Phase 2 — Score & Select

Score every item on this rubric. The three named criteria are the plugin's stated priorities; the fourth exists because the whole premise is three fixes fitting in one coherent PR.

| Axis | Weight | 0 | 1 | 2 | 3 |
|---|---|---|---|---|---|
| Token frugality | ×3 | no effect | trims occasional output | removes repeated model derivation | moves a per-invocation cost into a script or removes it |
| Code quality | ×2 | cosmetic | clarifies guidance | prevents a recurring class of defect | closes a correctness or data-loss gap |
| Speed | ×2 | no effect | saves a step sometimes | removes a round-trip | removes a whole phase or stall |
| Cost to fix | ×1 | multi-skill redesign | new script + several edits | one file, localized | a few lines in one file |
| Cost if it ships wrong | ×2 | a cosmetic miss nobody acts on | misleading prose someone notices | a rule that silently misfires until spotted | a wrong rule that corrupts output or loses data |

**Cost if it ships wrong** is scored against the *unverified* version of the fix: if this landed with nobody driving it, what would it take to notice and undo? Token frugality prices what a probe spends, which is a few commands; this axis prices what skipping the probe costs, which is a whole second pass — harvest, score, fix, verify, PR. Those are not symmetric, and without the axis the rubric ranks verification-discipline items below cheaper cosmetic ones. Score it from the failure mode, not from your confidence in the fix.

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
2. **If the change is a decision rule, drive it.** A heuristic, a gating condition, a base-ref choice, a skip criterion — anything a later run must *apply* rather than read — is not verified by read-back. The text can be correct and the rule still never fire. Build the smallest real input that exercises it (a throwaway commit, a fixture directory, a stub beside the script) and observe the rule both **firing** and **declining to fire**, then report both observations. A rule whose accept and reject cases have not each been seen is unverified, exactly as an unexercised script is under step 4.
   Edits with no accept/reject behaviour of their own — a reworded convention, a stated preference, a clarified description — are documentation and finish at step 1. Say which of the two an item is before verifying it, because that choice decides what counts as done.
3. For an edited `SKILL.md`: run the structural items of the **Review Checklist** in `${CLAUDE_PLUGIN_ROOT}/skills/write-skill/SKILL.md` against it — frontmatter, plugin-main.md first, one-question-per-turn, banner, edge cases. The new-skill items (README row, single-file justification) do not apply when editing an existing skill.
4. For an added or edited script: `bash -n <file>`, then execute it once on real input and confirm the output matches its documented contract. A script whose contract is unexercised counts as unverified.
5. Grep for stale references to anything renamed, removed, or re-scoped — comments and docs that still describe the old behavior are part of the fix, not follow-up.

If an item cannot be verified, revert its commit, return it to the backlog, and say so. Never ship an unverified item to keep the count at three.

## Phase 5 — Finalize

1. **ADR check:** apply **ADR Awareness** from `plugin-main.md` against the changed files before pushing.
2. Push the branch.
3. Open **one** PR via `gh pr create`, titled `chore: self-heal — <n> backlog items`. Body: one section per item giving the source (`#<issue>` item `<index>`), the ask, what changed, and how it was verified. Link every source issue; add `Closes #N` only for an issue whose every item is in this PR.
4. Per source issue, `gh issue comment` naming which items this PR addressed, which were already satisfied in the tree, and which remain open.
5. **Before closing any issue, carry its leftovers forward.** Re-read the issue body and list the items this PR did not address. If any remain, either leave the issue open, or — when the issue is being closed anyway — file a fresh issue containing those items *verbatim*, each tagged `_Carried from #<N> item <M>._`, and link it from the closing comment. Closed-issue bodies are only visible by re-reading them, so an item dropped at close time is effectively unrecoverable. Close an issue only once nothing is left in it or its leftovers are carried.
6. Report the PR url, which items stayed in the backlog, and any carry-forward issue you filed.

## Handoff Contract with `bf:self-audit`

`bf:self-audit` files findings; this skill harvests and fixes them. The two halves only stay compatible if the pairing is actually run end to end, so exercise it rather than reading an audit's findings straight out of the script's JSON. What to watch, and what has already been observed:

| Contract point | Status |
|---|---|
| A filed issue body segments into one item per finding | Holds. The `### ` heading the audit writes is a delimiter `harvest-issues.sh` splits on; older `- **bold**` bodies split too. A body using neither arrives as a single item. |
| The `audit-id` fingerprint prevents re-filing | Holds for open issues, and for not-planned closures via `--settled`. It cannot express "fixed in a branch that has not merged yet". |
| The axes an audit assigns match the axes this rubric scores | Partly. The audit assigns token-frugality, code-quality and speed; the rubric also scores cost to fix and cost if it ships wrong, neither of which a finding carries. Score those here. |
| Filed findings stay valid until healed | **Does not hold.** Findings go stale as the tree changes — a run may find a large share already fixed. This is why Phase 2 requires reading the implicated files before scoring, and why the issue comment in Phase 5 names what was already satisfied. |

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
