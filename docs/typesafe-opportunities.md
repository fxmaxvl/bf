# TypeSafe in bf

Where a typed judgment (TypeSafe System One / Jev) earns its place in this plugin: what is wired,
what is a candidate, and what deliberately stays deterministic. Full sweep of all 26 skills and 18
scripts, 2026-09-21.

**Opt-in, always.** `/bf:typesafe on` verifies a key with a live smoke call and sets
`typesafe.enabled` in `~/.bf/config.json` (beside `parallel_audit`; the key stays in
`$TYPESAFE_API_KEY` and is never written to disk). Every call site goes through
`skills/typesafe/scripts/typesafe-ask.sh`, which exits `3` on anything — off, no key, 401, rate
limit, timeout, malformed reply — and the caller falls back. A boost that breaks when removed is a
dependency, not a boost, and does not ship.

**The shape, everywhere:** code enumerates candidates, a judgment selects among them, code slices
the original text. A boosted run can pick wrong; it cannot invent content that was not in the
source. Known rules, calculations, exact lookups and execution stay in code.

API shapes below are from the live docs (verified 2026-09-21): `POST
https://api.typesafe.ai/v1/systemone`, body `{state, model: "jev-latest", questions}`. Choice
returns `{choice, confidence, probabilities}`; noul returns `{noul: 0..1}`; score takes an **ordered
array** of 2–10 level descriptions and returns a fractional position plus `confidence` and `legend`.

---

## Wired today

| Site | Fires when | Without a key |
|---|---|---|
| `self-heal/scripts/boost-segments.py`, called by `harvest-issues.sh` | An issue body used neither `### ` nor `- **`, so the sniffer left it as one item | One lump item, as before |
| `self-audit/scripts/audit-static.sh` | A `x/SKILL.md` ref survived the denylist *and* does not exist — usually zero per run | Every unresolved ref filed, as before |
| `feature/scripts/check-report-status.sh` | The `^STATUS:` grep missed and the file exists | `NOT_FOUND`, as before |

Each was verified in three directions: boosted branch fires, judgment declines, TypeSafe
unavailable — and in the last case the output is byte-identical to the pre-change baseline.

Two notes that constrain future work here:

- **Segmentation ids are cached** by body digest in `~/.bf/cache/typesafe-segments.json`. Without
  that, `--item 34:3` in the fix pass could point at different text than the scoring pass scored.
- **No judgment may reach an `audit_id`.** Those fingerprints exist so later runs dedupe against
  filed issues. Suppression is fine (the finding returns under the same id); a judged fingerprint
  is not. `audit-static.sh` reports its suppression count in `notes[]`, because with a judgment in
  the loop the finding list is no longer reproducible from the repo alone.

---

## Candidates, ranked

### A. `scan-conventions` Phase 2 — relevance filter

**Today:** "1. Read the file content. 2. Decide whether it is relevant to `TASK_DESCRIPTION`." Every
discovered convention file is pulled into context *in order to decide whether it mattered*. This is
reached from `plugin-main.md`'s Custom Convention Discovery, so it is hot across every skill.

**Design.** `discover-conventions.sh` already returns `{filename, tier, first_heading, path}`. Add
the first ~500 characters, then one **noul** per file — "this convention would meaningfully
constrain work on the described task" — with `state` = `{task, filename, first_heading, excerpt}`.
Code reads only the files that pass. No key → read them all, exactly as today.

**Win: token frugality ×3** on the plugin's own rubric — "moves a per-invocation cost into a script
or removes it." Strongest candidate on the list for that reason.

### B. ADR Awareness — `conventions/plugin-main.md` step 3

**Today:** before every commit/push/PR in `feature`, `quick` and `micro`: "Compare the session's
changed files and decisions against those titles. Flag a match only when the change plausibly
contradicts, supersedes, or materially extends a recorded decision." A soft instruction at the
busiest moment in the workflow — cheap to skip, and unverifiable when it is skipped.

**Design — keep it script-internal.** `resolve-adr.sh` is already called at step 1 and already
returns `adrs[].title`. Give it an optional `--change-summary "<text>"` and one **noul** per ADR
title, returning an extra `affected: [{number, title, probability}]`. Step 3 then reads a field
instead of instructing a comparison, and the fallback is the current prose. Titles only, so the
request stays small and no ADR body is read unless something is flagged.

Highest-frequency candidate here, and the one where the deterministic path is weakest — not wrong,
just optional.

### C. `feature/collect-todos` steps 2–3 — relevance and reason

**Today:** for every TODO found in the diff, the model judges "clearly related to the feature or
`[?]`", then classifies the reason into a fixed set of four
(`temporary-solution`, `dependency-limitation`, `incomplete`, `tech-debt`).

**Design.** Per TODO, asked together in one request: one **noul** for feature relevance and one
**choice** over the four reasons, `state` = `{feature_slug, comment_text, surrounding_code, path}`.
Code writes the table. The four categories are already written as a fixed set, which is a `criteria`
map verbatim. Without a key the model classifies in prose, as today.

**Win: a per-item derivation leaves the main turn**, and the labels stop drifting between runs.

### D. `micro` Phase 4 — the gate-skip guard

**Today:** skip both quality gates when every changed entry is a pure rename (`R100`) or "a
modification whose added and removed lines differ only in a path or module string." The first half
is mechanical; the second is a judgment stated in prose.

**Design.** One **noul** per modified file: "the added and removed lines differ only in a renamed
path or module string." **This is the one site where a wrong answer removes a check rather than
adding a finding**, so it must inherit the existing asymmetry — the prose already says "when the
diff is mixed or unclear, run them." High bar to skip (≥0.9), and any unavailability, any
uncertainty, or any file the judgment declines means both gates run.

### E. `self-heal` Phase 2 — the scoring rubric as Score features *(deferred, not rejected)*

The four-axis rubric is already written as 0–3 levels of concrete situations — a `score` `criteria`
array almost verbatim, once each cell is rewritten to stand on its own (`no effect`, `cosmetic` do
not). Code keeps the ×3/×2/×2/×1 weights, the no-file-overlap tiebreak and the top-N cut.

**Deferred for two reasons.** It is the only candidate living in SKILL.md prose rather than a
script, so it puts a two-path branch in front of every reader of that file; and its real payoff —
scores comparable and persistable across runs, so a re-run only scores new items — needs a store
that does not exist yet. Revisit when the selection artifact grows a machine-readable side.

### F. Smaller

- **`feature/scripts/read-block.sh`** — exact header match, documented to miss `## Specification`
  when asked for `## Spec`. Fallback only: on a miss, a **choice** over the file's actual `## `
  headings plus a `none` option.
- **`pr-comments` Phase 1 grouping** — "group comments that make the same point across files."
  Pairwise **noul** over pairs code pre-filters by file/keyword overlap. The rule that a group
  carries every member's `thread_id` stays in code; a lost id leaves a public thread open forever.

---

## New capability, not a fragility fix

Listed separately because "boost" here changes what the plugin *does*, rather than fixing what it
gets wrong:

**`autopilot` Step 1 routing.** Today the first word is matched exactly against a five-entry table
and anything else routes to `feature`. So `/bf:autopilot fix the login bug` runs the full
brainstorm→spec→design workflow for a bugfix that `quick` would handle. A **choice** over
`{feature, quick, micro, review, design}` with `state` = the raw arguments turns that default into a
routing decision (the docs call this intent-routing). Two guards if it is ever built: an explicit
first-word match always wins without asking anything, and an unconfident answer falls back to
`feature`, today's default.

---

## Non-candidates

Ruling these out matters as much as the list above.

| Code | Why it stays deterministic |
|---|---|
| `feature/scripts/detect-stack.sh` | File existence and `package.json` key lookups |
| `feature/scripts/changed-packages.sh`, `coherence/scripts/scope.sh` | git plumbing, glob matching, `@@` hunk counting |
| `feature/scripts/init-probe.sh` | `--quick`, `GH-ISSUE:<n>`, Jira URL — exact tokens |
| `pr-comments/scripts/{fetch-pr-comments,wait-for-review,post-replies}.sh` | GraphQL over typed fields; polling with a timeout |
| `adr-writer/scripts/resolve-adr.sh` (numbering) | Filename globs and `printf '%04d'` |
| `feature/scripts/{state-ops,finalize-git,cleanup}.sh`, `autopilot/hooks/*` | JSON state, `git status --porcelain`, hook install |

**Already model judgment inside an Opus turn — not boost targets.** `complexity-gate`'s red-flag
scan, `consistency-gate`, `bug-fix`'s root-cause ranking, `walkthrough` Phase 2 ranking, `review`'s
findings and severity mapping, `gh`/`jira` issue classification, `pr-comments` triage verdicts.
These run with the diff and the conventions already in context; handing them to a smaller judgment
model is a downgrade. The exception is when one of them starts handling long lists, where
comparable per-item numbers would beat prose.

**No script, nothing to boost:** `onboard-skill`, `research`, `session-summary`, `design`,
`discuss`, `consilium`, `decide`, `teach`, `write-skill`, `jira`, `bug-fix`, `gather`. All
interactive, generative, or oracle skills whose output is prose for a human, with no fixed answer
set and no parsing step. Checked, not skipped.

---

## Thresholds

No number in this document is calibrated. The `autoformat` cookbook deliberately uses
context-dependent bands (0.2 after a dangling line, 0.5 after terminal punctuation) rather than one
cut, and the shipped sites follow that spirit: 0.5/0.7 for segment boundaries depending on whether
the line follows a blank, 0.7 for placeholder suppression, 0.8 for a recovered verdict, and a
proposed 0.9 for the gate-skip guard because that one removes a check. Evaluate them against this
repo's own data before trusting any of them.
