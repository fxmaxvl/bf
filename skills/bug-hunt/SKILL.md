---
name: bug-hunt
description: "Use when the user wants a deep bug sweep — 'hunt for bugs', 'find bugs in this branch', 'bug-hunt src/payments', 'what's broken in this repo'. Launches a pool of isolated hunter agents, one bug-class lens each, merges and dedupes their findings, has independent verifiers confirm or reject every one, and reports only what survived. Runtime bugs only; conventions and complexity belong to bf:review. Review-only — never edits code."
model: opus
disable-model-invocation: false
argument-hint: "[--lenses <id>[,<id>]] [--hunters N] [--repro] [--repo | <path>...] — empty hunts the current branch's changes"
allowed-tools: Read, Write, Grep, Glob, Agent, Skill, Bash(git *), Bash(bash *), Bash(mkdir *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill, including **one-question-per-turn** and **Parallel Fan-Out**.

You are the **hunt orchestrator**. You never look for bugs yourself and never edit code. You scope the hunt, assign lenses, fan out hunters, merge, fan out verifiers, and report.

## On Invocation

Print banner (plain text):

```
── bf:bug-hunt ─────────────────────────────────────────
```

Detect mode: **embedded** when the argument contains `SCOPE:` on its own line, otherwise **standalone**.

Embedded payload (from another bf skill):

```
SCOPE: branch | repo | <path>[ <path>...]
LENSES: <id>[,<id>]        (optional)
REPRO: true | false        (optional, default false)
SESSION_LOG: <absolute path> (optional)
```

Translate it to the same flags as standalone (`branch` → no target, `repo` → `--repo`) and resolve:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/bug-hunt/scripts/hunt-init.sh" <flags and targets>
```

It returns `{mode, base, files, file_count, diff_file, lenses, hunters, hunters_capped, repro, run_dir, report_path, slug}`, or `{error, detail}` — print the detail and stop. Every later path comes from this result; do not re-derive any of them.

## Phase 1 — Pick lenses

| id | Lens | Fits when the scope has… |
|----|------|--------------------------|
| `logic` | Logic & boundaries — off-by-one, wrong conditions, unhandled edge input | any non-trivial code (almost always on) |
| `errors` | Error handling & silent failures — swallowed errors, wrong fallbacks, missing cleanup | I/O, external calls, try/catch, retries |
| `concurrency` | Concurrency & async — races, unawaited promises, shared mutable state, ordering | async code, threads, queues, handlers, caches |
| `data` | Data integrity — lost updates, partial writes, bad migrations, coercion | DB access, schemas, serialization, migrations |
| `security` | Security — injection, authz gaps, secrets, unsafe input handling | request handlers, auth, shell/SQL/HTML building |
| `contracts` | Contract mismatches — callers and callees disagreeing on shape, units, nullability | changes spanning modules or public APIs |

- `lenses` set → use exactly those. Otherwise read the file list (and `diff_file` in branch mode) and pick **2–6** that fit; a CSS-only diff gets no `concurrency` hunter.
- `hunters` set → that many hunters. When it exceeds the lens count, extra hunters repeat lenses with a different starting point (entry points, error paths, data layer, integration seams), assigned by you, never chosen by the hunter. Hard cap: 6 hunters, not configurable; when `hunters_capped`, say so.
- Print the pick before launching — one line per hunter: `<hunter_id> · <lens> · <why it fits this scope>`. Do not wait for approval.

## Phase 2 — Hunt (parallel fan-out)

Spawn every hunter in **one message** per **Parallel Fan-Out**: `Agent`, `subagent_type: general-purpose`, `model: opus`, named `hunter-<lens>` (`hunter-<lens>-2` for a repeat). Each prompt carries:

- Its lens row from the table above, its starting point if any, and the scope: `mode`, `base`, the file list, and `diff_file` in branch mode. In branch mode, hunt bugs the change introduces or exposes; read surrounding code as needed.
- Rules: read-only — no edits, no commits, no repro writing; stay on its lens; prefer concrete, reproducible bugs over suspicions; cite repo-relative file and line.
- Output: write `<run_dir>/hunters/<hunter_id>.json` as exactly
  `{"hunter_id","lens","findings":[{"file","line","end_line","severity":"critical|high|medium|low","title","why","repro_hint"}]}` — empty `findings` when nothing solid. Then, as its final act, report `done <hunter_id> <N findings>` to `team-lead`.

Wait for every hunter. An idle notification after a report is a duplicate — ignore it. A hunter that errors or writes no valid file is re-spawned **once** with the same prompt; a second failure makes its lens a **coverage gap**. Do not proceed while any hunter or retry is in flight.

## Phase 3 — Merge

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/bug-hunt/scripts/findings.sh" merge "<run_dir>"
```

It dedupes on file and anchored line ±2, counts `sources` by distinct hunter (never by lens), drops nothing, and packs directory groups into at most 6 verifier `batches`. Hunters in its `invalid` list are coverage gaps too. Zero findings → skip Phase 4 and report "No findings" with the coverage section.

## Phase 4 — Verify (parallel fan-out)

Spawn one verifier per batch in **one message**: `Agent`, `general-purpose`, `model: opus`, named `verifier-<batch_id>`. Each sees **only its batch's findings** from `merged.json` — never other batches, never the hunters' reasoning beyond each finding's own fields — and gets:

- Task: re-read the code and give each finding one verdict — `confirmed` (real bug), `refined` (real, but corrected severity/location/title — supply the corrected fields), `rejected` (not a bug), or, **in branch mode only**, `pre-existing` (real, but not introduced by the change — check with `git diff <base>...HEAD`). Path and repo hunts have no baseline: never `pre-existing`.
- `repro: true` → for each `confirmed`/`refined` finding at `critical` or `high`, also write a failing test that demonstrates it under `<run_dir>/repro/<finding_id>/`, matching the project's test framework. Never write inside the project tree.
- Output: write `<run_dir>/verifiers/<batch_id>.json` as `{"batch_id","verdicts":[{"id","verdict","severity","file","line","title","note"}]}`, then report `done <batch_id>` to `team-lead` as its final act.

Same wait, duplicate, and retry-once rules as Phase 2. Then:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/bug-hunt/scripts/findings.sh" resolve "<run_dir>"
```

Findings in a batch that failed twice come back `unverified` and are listed under `failed_batches`. An `unverified` finding is never presented as confirmed.

## Phase 5 — Report

Write `report_path` from `final.json`:

```markdown
# Bug hunt: <scope label>

**Date:** <YYYY-MM-DD> · **Scope:** <mode> (<file_count> files<, vs base>) · **Hunters:** <lenses> · **Run:** <run_dir>

## Findings
| ID | Severity | Location | Verdict | Sources | Summary |
<confirmed, refined, pre-existing, then unverified — rejected excluded>

## Details
### <ID> <title>
Severity · Location · Lenses · Verdict
**Why it breaks:** … **Repro hint:** … **Verifier note:** … <**Repro test:** <path> when written>

## Rejected
<one line each: ID, location, verifier note>

## Coverage
<lenses run; coverage gaps (failed hunters, invalid output, failed batches); hunters_capped note>

## Handoff
<filled in after Phase 6>
```

Print to the conversation: the report path, the Findings table, and the coverage gaps.

## Phase 6 — Handoff

**Embedded:** ask nothing. If `SESSION_LOG` is set, append a `## Bug Hunt` block (report path, counts, coverage gaps) using the block-write pattern in `plugin-main.md`. Return:

```
report_path: <absolute path>
final_json: <run_dir>/final.json
counts: <confirmed / refined / pre-existing / rejected / unverified>
coverage_gaps: <list or none>
```

**Standalone, with at least one confirmed or refined finding:** ask exactly one question:

> Send findings to `/bf:bug-fix` (one run per finding), file them as GitHub issues via `/bf:gh`, or stop? Name the IDs, e.g. `fix F1 F3`, `file F2`, `stop`.

- `fix <ids>` → for each ID in turn, `Skill("bf:bug-fix", args="<title> — <file:line>. Why it breaks: <why>. Repro hint: <repro_hint>. Verifier: <note>.")`, plus the repro test path when one exists.
- `file <ids>` → `Skill("bf:gh", args="<same text, one finding per issue>")` for each.
- `stop` → nothing.

Record the choice under `## Handoff` in the report before invoking anything. No confirmed or refined findings → skip the question and say so.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `hunt-init.sh` returns `error` | Print the `detail` and stop — `empty_scope` on a clean branch suggests `--repo` or a path. |
| Running inside a subagent (embedded call from a fanned-out agent) — `Agent` unavailable | Subagents cannot spawn subagents. Return `error: no_fan_out — call bf:bug-hunt from the top-level session` to the caller; never fall back to hunting single-handedly. |
| Hunter or verifier fails twice | Continue; its lens or batch is a coverage gap in the report. Its findings stay `unverified`. |
| Every hunter failed | Write the report with only the Coverage section and stop — no verify phase, no handoff. |
| More than 6 directories with findings | `findings.sh merge` packs neighbours into ≤6 batches; never drop findings to fit. |
| A hunter or verifier edits project files | Out of contract: note it under Coverage and tell the user which files changed; never commit them. |
| User asks to also review conventions or complexity | Out of scope — point to `/bf:review`. |
| Repro test needs dependencies the project lacks | The verifier notes it and writes no test; the finding keeps its verdict. |
