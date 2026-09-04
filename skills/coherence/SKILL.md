---
name: coherence
description: Use after adding to or editing existing code — especially before committing, or when new behavior was bolted onto an existing method — to check whether the change left the code coherent. Assesses the change against the engineering guidelines' breakage kinds (abstraction, encapsulation, contract, readability, consistency, cohesion) and reports what must be refactored versus merely noted. Works standalone, outside any bf workflow.
model: opus
disable-model-invocation: false
argument-hint: "[empty for uncommitted changes | 'branch' | <sha or range> | <paths>]"
allowed-tools: Read, Edit, Grep, Glob, Bash(bash *), Bash(git *), Bash(rtk *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Fast, standalone coherence check on a code change: did it leave the code it touched making sense?
Answers the question the guidelines' §3 asks, on demand, in any session — no branch, no report
files, no workflow state.

**Not `/bf:review`.** That is the heavyweight pre-PR gate (parallel review + complexity +
consistency agents, persisted report, fix rounds). This is a single-pass check of one change
against one convention, cheap enough to run after every edit.

## On Invocation

Print banner (plain text, not in a code block):

```
── bf:coherence ────────────────────────────────────────
```

Resolve the scope in one call — do not derive diffs by hand:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/coherence/scripts/scope.sh" "$ARGUMENTS"
```

It returns `{root, mode, file_count, added, removed, files[]}`. `mode` is `working` (uncommitted),
`branch`, `range`, or `paths`. If `error` is `not_a_git_repo`, print `Not a git repository. Exiting.`
and stop. If `file_count` is `0`, print `STATUS: NOTHING_TO_ASSESS` and stop — spawn nothing, read
nothing.

Print one line: `Scope: <mode> — <file_count> file(s), +<added>/-<removed>`.

## Phase 1 — Load the standard

Resolve `guidelines` via the 3-step Convention Lookup in `plugin-main.md` and read it in full. Its
§3 breakage table is the **only** checklist for this skill — do not invent categories, and do not
substitute your own taste for it. If the file is missing at all three tiers, say so and stop; there
is nothing to check against.

## Phase 2 — Assess at feature-slice radius

Read the full current content of each changed file — not just the diff hunks. A diff cannot show
whether the enclosing unit still holds together, which is the entire question here.

Then widen to the **feature slice**: for each changed file, find its direct collaborators — what it
imports and what imports it:

```bash
git grep -l "<module-or-symbol-name>" -- . | head -20
```

Read the collaborators that participate in the changed behavior. Stop there — direct collaborators
only, not the transitive closure.

For each changed unit, walk every row of the §3 table and record a verdict. Then apply §3's two
bounding rules literally:

- **Judge the end state, not the diff** — assess the code as it now stands.
- **You own what you break or worsen** — breakage the change introduced or deepened is in scope.
  Pre-existing breakage the change neither touches nor worsens is a note, never a fix.

## Phase 3 — Report

Print findings in exactly two buckets, most severe first. Cite `file:line` for each.

```
MUST FIX (change made it broken)
  <file:line> — <kind>: <what broke, and the smallest fix>

NOTED (pre-existing, not worsened)
  <file:line> — <kind>: <what it is>
```

Close with one of:

- `STATUS: COHERENT` — nothing in the MUST FIX bucket. Say so plainly; do not pad the NOTED bucket
  to look thorough. "I re-read it and it still holds together" is a real result.
- `STATUS: N FINDING(S)` — the MUST FIX bucket is non-empty.

An empty MUST FIX bucket is the expected outcome for most small changes. Manufacturing findings to
justify the run is a worse failure than missing one.

## Phase 4 — Apply

Only when the MUST FIX bucket is non-empty. Ask exactly ONE question and wait:

> Apply the MUST FIX refactors? (all / pick by number / none)

- **all** / **pick** — apply the selected fixes with `Edit`. Touch nothing in the NOTED bucket.
  After editing, re-read each edited unit once and confirm the finding is actually resolved.
- **none** — stop. The report stands.

Never apply a NOTED item, even if asked to "fix everything" — say which items you skipped and why.
Report what you changed against the findings you stated; do not claim a fix you did not verify.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Not a git repository | Print `Not a git repository. Exiting.` and stop |
| Empty scope (`file_count: 0`) | Print `STATUS: NOTHING_TO_ASSESS` and stop; read nothing |
| `guidelines.md` missing at all 3 tiers | Report the resolved paths tried and stop — there is no standard to check against |
| Diff is pure config/lockfile/generated output | Report `STATUS: COHERENT` with a one-line note that there is no logic to assess |
| Very large scope (>25 files) | Assess the changed files, but skip collaborator widening and say so — an unbounded slice is the sprawl §3 exists to prevent |
| Invoked mid-`/bf:feature` or `/bf:quick` | Those workflows already apply the guidelines; note the overlap in one line and run only if the user asked explicitly |
| Findings are all stylistic preference | They belong in NOTED, not MUST FIX. Style matching is §3's rule; your taste is not |
