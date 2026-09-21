---
name: self-audit
description: Use when asked to audit the plugin, check the skills for convention drift or token waste, or find what needs fixing in bf itself. Sweeps every skill, script, and convention for drift, stale references, and token waste, then files the findings as GitHub issues for /bf:self-heal to fix.
model: opus
disable-model-invocation: false
argument-hint: "[optional: scope like 'skills/review', or '--static-only' to skip the judgment pass]"
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Audit this plugin against its own conventions and file what it finds as GitHub issues.

**This skill never edits the plugin.** It finds and files; `/bf:self-heal` picks the top items and fixes them. Keeping the halves separate is what lets findings be ranked against each other before any code moves.

## On Invocation

Print banner (plain text):

```
── bf:self-audit ────────────────────────────────────────
```

1. `git rev-parse --show-toplevel` — the plugin repo to audit.
2. **Guard:** if there is no `skills/` directory under it, stop — this skill audits the bf plugin repo, run it there.
3. If `$ARGUMENTS` names a scope (a path under `skills/` or `conventions/`), restrict every phase to it and say so in the report.

## Phase 1 — Static Sweep

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/self-audit/scripts/audit-static.sh"
```

Returns `{root, counts, findings[], notes[]}`. Each finding carries a stable `audit_id` — the fingerprint that keeps repeat runs from re-filing the same thing.

These checks are mechanical and already settled: frontmatter fields, `name`/directory agreement, the `plugin-main.md` read line, banners, `## Edge Cases`, absolute path literals, broken `${CLAUDE_PLUGIN_ROOT}` and sub-skill references, README rows in both directions, `bash -n`, executable bits, orphaned scripts. **Do not re-check any of them by hand** — read the JSON and move on.

## Phase 2 — Judgment Sweep

Skip this phase if `$ARGUMENTS` contains `--static-only`. It skips only this phase — the mechanical findings still dedupe, still get your approval, and still get filed.

What remains needs reading comprehension, so fan out three **read-only** lenses per **Parallel Fan-Out** in `plugin-main.md`: named agents, dispatched in a single message, all three awaited before anything is merged, no messaging between them. Give each the repo root, the scope, and the Phase 1 findings so nobody re-reports a static hit. Each returns a list of findings in the Phase 3 shape — and edits nothing.

| Agent | Looks for |
|---|---|
| `drift-lens` | Divergence from `plugin-main.md` and the engineering guidelines that grep cannot see: questions batched into one turn, artifacts written outside `.bf/`, hard-coded convention paths instead of the 3-step lookup, internal process names leaking into durable records, fan-out that skips the atomic wait. |
| `token-lens` | Work the model is asked to do that a script should: derivation repeated every invocation, unbounded `git`/`gh` output, whole-file reads where the block-reading pattern applies, prose duplicated across skills that belongs in `conventions/`. |
| `coherence-lens` | Instructions that no longer match reality: prose describing removed behavior, a phase flow that disagrees with its own phase list, a skill citing another's phases inaccurately, a README row that oversells what the skill does. |

Every finding must cite `path:line` and name the convention or cost it violates. A lens that cannot cite is reporting a hunch — drop it.

## Phase 3 — Merge & Dedupe

1. Merge the static and lens findings. Where a lens restates a static finding, keep the static one — it has the stable id.
   `audit-static.sh` always sweeps the whole repo, so if a scope was given, drop static findings whose `path` falls outside it here.
2. Assign any finding without one an `audit_id` of `<check>:<path>[:<symbol>]`.
3. **Dedupe against the live backlog.** Fetch the existing items (full bodies — no `--brief`, the fingerprint sits at the end of each item) together with the settled fingerprints:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/self-heal/scripts/harvest-issues.sh" --settled
   ```
   Drop every finding whose `audit_id` already appears in an open item, **and** every finding whose `audit_id` appears in `settled_audit_ids` — those were filed, considered, and closed as not-planned, so re-filing them relitigates a settled call. Report the two counts separately; a run that files nothing because everything is already tracked or already settled is a success, not a failure.
4. Group the survivors into categories: **convention drift**, **stale references**, **token waste**, **structural gaps**.
5. Rank within each category by the axes a fix would move (token frugality, code quality, speed) and by how localized it is — this is the signal `/bf:self-heal` scores on, so a finding that cannot name an axis is not worth filing.

Write the full result to `<artifact_root>/audit/<YYYY-MM-DD>-audit.md` (artifact root per **Generated Artifacts** in `plugin-main.md`), including the deduped and dropped findings so the next run has the history.

Print the grouped findings with counts, then ask (one question only):

> File these as issues? Reply `yes`, a category or ids to file, or `no`.

## Phase 4 — File Issues

File **one issue per category**, not per finding — `/bf:self-heal` selects across items inside issues, and a backlog of single-finding issues defeats its ranking.

Title: `audit: <category> — <n> findings`. Label: `audit` (check `gh label list`; create with `gh label create "audit" --repo <owner/repo>` if absent).

Each finding becomes one `### ` section. Use headings, not bullets — `self-heal`'s harvester segments on either, but headings give it clean item titles instead of a truncated first sentence:

```markdown
### <imperative title, under 80 chars>

<what is wrong, citing `path:line`>

**Why it matters:** <one line — the cost, not the rule>
**Fix:** <the narrowest change that resolves it>
**Axes:** <token-frugality, code-quality, speed>
`audit-id: <audit_id>`
```

The `audit-id` line is load-bearing: it is how the next run knows this is already tracked. Never omit it, and never reword an existing one.

If a category exceeds 8 findings, split it by severity into two issues rather than filing one unrankable wall.

## Phase 5 — Report

Print the filed issue urls, the number deduped away, and the artifact path. Close with the handoff: `/bf:self-heal` will rank these against the rest of the backlog and fix the top three.

## Edge Cases & Errors

| Condition | Handling |
|---|---|
| `audit-static.sh` returns `{"error":...}` | Surface `detail` and stop — `not_plugin_repo` means you are outside the bf repo. |
| A finding matches a `settled_audit_ids` entry but you believe it is now valid | Do not silently re-file. Say which fingerprint was settled and why the situation changed, and ask once before filing. |
| No findings survive dedupe | Report "backlog already covers everything this run found" and exit without filing. |
| A finding targets `skills/self-audit/**` | File it like any other — but note the self-reference in the issue body so whoever fixes it knows the auditor is the subject. |
| `harvest-issues.sh` is missing or errors | Skip dedupe, warn that duplicates are possible, and continue — never skip filing over it. |
| A lens returns findings without `path:line` | Drop them and note the count; uncitable findings are not filed. |
| `gh` unauthenticated | Stop before filing, keep the artifact, and tell the user to run `gh auth login` then re-invoke. |
| A lens agent goes idle without reporting | Ask it once for its findings. If it stays silent, run that lens inline from the same brief, so the fan-out still completes — a partial fan-out is ruled out by the **Parallel Fan-Out** convention. Only if the inline pass also fails, record the gap in the artifact so the sweep is visibly incomplete rather than silently narrowed. |

Here is the request:
$ARGUMENTS
