---
name: walkthrough
description: Use when a change is finished and you want a guided read of it — after a build, before or just after committing, or when someone asks "walk me through what this does". Selects the hunks that carried a decision, explains each one including the alternative not taken, and asks the author why while the reasoning is still recoverable. Discussion never edits code; comments accumulate and one closing gate decides the batch.
model: opus
disable-model-invocation: false
argument-hint: "[empty for uncommitted changes | 'branch' | <sha or range> | <paths>]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(bash *), Bash(git *), Bash(mkdir *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

A guided read of a change the user just built: what it does, which decisions it carries, then a tour
of the hunks that involved a choice — one at a time, each open to discussion. The reasoning behind a
change is most recoverable in the minutes after it is written, and nothing else in the pipeline asks
for it.

**Not `/bf:review`.** That is the heavyweight pre-PR gate — parallel agents, a persisted report, fix
rounds. **Not `/bf:coherence`** either: that checks the change against the engineering guidelines.
This one asks the author *why*, and the author is the only one who can answer.

Only the standalone mode exists today. Running as a phase inside a code-generation workflow, and
rendering decisions a workflow already recorded, are not built.

## On Invocation

Print banner (plain text, not in a code block):

```
── bf:walkthrough ──────────────────────────────────────
```

Confirm a repo, then resolve the scope in one call — never derive diffs by hand:

```bash
git rev-parse --show-toplevel
bash "${CLAUDE_PLUGIN_ROOT}/skills/coherence/scripts/scope.sh" --with-diff "$ARGUMENTS"
```

If `git rev-parse` fails, or the call returns `error: not_a_git_repo`, print
`Not a git repository. Exiting.` and stop. Otherwise the call returns
`{root, mode, file_count, added, removed, files[], diff_file, whitespace_only_files[], hunks[]}`.
Each `hunks[]` entry is `{file, index, line, added, removed}`, where `line` is the line of that
hunk's `@@` header inside `diff_file` — read hunk bodies and header text out of that file. There is
no end marker: a hunk runs to the next `^@@` or `^diff --git` line, or to EOF. The next entry's
`line` is not that boundary — it may sit in a different file, past an intervening header block.

Untracked files are never in scope — every mode diffs tracked content, so a brand-new file is
invisible until git knows about it. Run `git status --porcelain -uall` before going further (`-uall`
so the entries are files, not a collapsed directory); if it lists `??` entries, print one line
naming them and noting that `git add -N <path>` brings a new file into scope. Say nothing when
there are none.

If `file_count` is `0`, print `STATUS: NOTHING_TO_ASSESS` and stop — spawn nothing, read nothing.

Print one line: `Scope: <mode> — <file_count> file(s), +<added>/-<removed>`.

## Phase 1 — Mechanical filter

Drop only what a rule can decide, working from the facts the script already returned:

- **Path exclusions** — lockfiles, generated output, vendored directories, binaries.
- **Whitespace-only files** — every file listed in `whitespace_only_files`. The field is named for
  the common case; it holds every file with no hunk left under `git diff -w`, which also catches
  binaries, pure renames and mode-only changes. None of them has a hunk to tour, but say which kind
  it was if the not-toured line would otherwise call a binary content change whitespace. The kind
  comes from that file's `diff --git` header block in `diff_file` — `Binary files … differ`,
  `rename from`/`rename to`, or `old mode`/`new mode`.
- **Oversized hunks** — more than 150 changed lines in one hunk. That number is a chosen default,
  not derived from anything; tune it if it drops hunks that mattered.

Stay at that coarsest level and no finer. This filter is verified by reading it, not by tests, so
being obviously correct on a read is the only verification it gets — and every rule added below
path-and-whitespace level costs exactly that.

**Do not attempt imports-only classification here.** It looks mechanical and is not: import syntax
differs per language, spans several lines in Java and Rust, and is indistinguishable from a string
literal without a parser. Worse, it is wrong precisely on the case that matters most — a hunk that
adds an import *and* a call site is decision-carrying, and a regex sees only the import. Imports are
judged in Phase 2, where reading the hunk can tell the two cases apart.

## Phase 2 — Rank what survived

Read each surviving hunk out of `diff_file` and ask one question of it: **what does this do to
behaviour?** Rank on the answer. What to weight:

- A value that changes what the system does — a timeout, a retry count, a limit, a default flipped.
- A branch, guard, or error path added, removed, or inverted.
- A contract change — signature, return shape, or a name that now promises something different.
- A dependency or call newly reached, or no longer reached.
- Anything where a different reasonable choice existed and one was picked.

**Weight consequence, not only structure.** A timeout changed from 30s to 5s, a retry count, a
default flipped to false are structurally trivial one-liners and very often the most consequential
lines in the whole change. Criteria indexed on signature changes and control-flow shape will rank
those last and reliably skip them — which is the failure this rule exists to prevent, so do not
tighten it back toward structural signals.

Hard cap of **8**, presented in **diff order** — predictable, and it matches every other view of the
change. Call-path order would require inferring a path that may be wrong and costs the reader the
ability to place a snippet in the change. If more than 8 qualify, offer to continue after the eighth
rather than truncating silently.

Excluded *and* demoted hunks feed one collapsed line that **names the files** plus a count:

```
Not toured: package-lock.json, src/gen/api.ts, src/net/retry.ts,
src/net/backoff.ts, src/util/env.ts, docs/api.md — 6 files
```

Names, because a count cannot tell a reader that the filter dropped something that mattered and a
filename can. Always name every file and let the list wrap across lines; anything that falls off
the end is invisible again, which is the exact problem naming files solves.

## Phase 3 — Opening overview

Two parts: **what was built**, and **the decisions the change carries**.

Standalone, decisions are inferred from the diff. Commit messages corroborate only and are never
primary input — an uncommitted tree has none, and real ones are often placeholders or squashed.

Put inferred decisions in a **separately titled section, hedged throughout**:

```
Decisions this change appears to carry
  Retries look capped deliberately rather than made unbounded — the ceiling is a literal, so
  the value may still be provisional.
```

The section boundary carries the provenance structurally, so a guess can never read as a record.
Per-item markers were rejected: they vanish the moment the reader skims, which is how terminal
output is normally read. Where the diff supports no conclusion, **say nothing** — silence over
invention.

Offer the whole set as **one block with one question**: "Anything there I got wrong?" One question,
not one per item — the tour will ask up to eight more times, and an opening that spends the user's
patience before the first snippet has already failed.

## Phase 4 — The tour

Each snippet, in this fixed shape:

1. **The hunk** — with a couple of lines of context, trimmed to what is needed to follow the point.
2. **What changed** — one sentence.
3. **Why** — including the alternative not taken where there was one. That is the one thing a diff
   can never show, and the reason the tour exists.
4. **What it affects** — callers or downstream behaviour, only when it is not obvious.

Then the prompt:

```
next  ·  comment <your note>  ·  skip <file>  ·  done
```

`skip <file>` surfaces a hunk the tour left out — the user names a file from the not-toured line and
it is presented under the same four-part shape. Path exclusion is a default, not a prohibition: a
named lockfile or generated file is surfaced too, since the user asked for it by name. If the file
has several hunks left out, present the highest-ranked one and say how many remain. Afterwards the
tour returns to the prompt for the snippet it was already on — a skip is a detour, it does not
advance. The verb always takes a filename; bare `skip` reads as "skip this snippet", the opposite of
what it means. `done` jumps straight to the closing gate with the batch intact.

Tone: interview, not narration. Where a rationale is uncertain, ask instead of asserting — **one
question at a time, never batched**. Plain language, short paragraphs, no internal process
vocabulary. Density is the main way a read like this goes unread.

## Phase 5 — The comment batch

A comment becomes a structured entry, four fields:

```
file:     src/net/retry.ts
hunk:     the backoff ceiling change
intent:   cap total retry time so a caller times out predictably
comment:  ceiling should come from config, not a literal
```

`intent` is the snippet's stated intent from Phase 4, carried along because the hand-off file
written at the closing gate is read with no tour context — each entry has to be actionable on its
own. Inline diff annotations were rejected for the same reason, plus one more: they bind to line
numbers that the apply-now branch invalidates as it edits.

**Discussion never edits code in the moment.** The batch lives in conversation context only, persists
across the whole tour, survives an early `done`, and reaches disk only at the closing gate.

## Phase 6 — Closing gate

Ask exactly ONE question over the whole batch, then wait:

> Apply these N comments now, or hand them off?

- **Apply now** — apply the comments to the working tree with `Edit`, then re-read each edited unit
  once and report what changed against the comments as stated. Do not claim a fix you did not
  verify.
- **Hand off** — resolve the artifact root (2-step lookup in `plugin-main.md`), `mkdir -p` the
  `.bf/walkthrough/` directory under it, and write the batch to
  `<date -u +%Y%m%dT%H%M%S>-walkthrough.md` there: the scope line as a heading, then one four-field
  entry per comment in tour order. The timestamp keeps two runs from colliding. Print the path that
  was written. There is no ephemeral session file outside a workflow run.

If the batch is empty, say so and skip the gate entirely.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Every hunk filtered in Phase 1 | Print the not-toured line naming the files, then stop — no tour, no gate |
| Very large scope (>25 files) | Do not read every hunk in Phase 2. Pre-rank from each hunk's `added`/`removed` counts plus its path, read only the top candidates in full, and say in the output that ranking was narrowed. 25 is a chosen default, matching `/bf:coherence`'s own large-scope guard |
| Invoked mid-`/bf:feature` or `/bf:quick` | Those workflows have their own review gates; note the overlap in one line and run only if the user asked explicitly |
| `mode` came back `branch` while the untracked probe listed `??` entries | The working tree was clean, so scope fell back to the branch diff — the tour is about to cover commits, not the new files. Say that in one line, then continue |
| `skip <file>` names a file with no hunk to surface — not in the change at all, or in `whitespace_only_files` | Say so in one line and stay on the current snippet |
| `diff_file` missing or unreadable | Report it and stop. Do not reconstruct the diff by hand — the point of the flag is that one call resolves it |
