# Codex CLI Compatibility

**Provenance:** commit `d373524dffd0238ca107f436cbf7869b4a7b8152`, branch `feat/codex-universal-support`, date `2026-08-03`.

This file is committed product documentation — in the same class as `README.md` — not a session-generated artifact. It intentionally lives under `docs/` rather than `.bf/`.

## Executive Summary

Codex support for the `bf` plugin is **not yet possible to confirm, and not yet advisable to attempt** — the parts of bf's format that overlap with Codex's documented conventions (`SKILL.md` + YAML frontmatter, a `scripts/` subdirectory, global and repo-local skill discovery paths) are genuinely compatible, but the parts that decide whether bf's *orchestration* survives the move — a plugin-root path variable, cross-skill invocation, and a subagent mechanism with per-call model routing — are unconfirmed one way or the other because no Codex CLI was available to run in this session. This document exists to make that gap legible and cheap to close: it inventories every coupling point with real numbers from this repo, grades every Codex-side claim by how it was established, and ships four small, explicitly untested probe files plus a numbered checklist so the next person with a Codex install can turn each unknown into a known fact in minutes.

## How This Was Determined

Every repo-side fact in this document was produced by a grep or `find` command run directly against this repository at commit `d373524dffd0238ca107f436cbf7869b4a7b8152` (branch `feat/codex-universal-support`, `2026-08-03`) — not estimated, not carried over from an earlier draft. Every Codex-side claim was produced by documentation research on Codex CLI conducted during this build. **No Codex CLI run occurred in this session.** No probe below has been executed; no Codex-side behaviour has been observed directly.

Because "documentation research" and "an actual run" are not the same strength of evidence, every Codex-side claim in this document carries one of three grades, and the grade travels with the claim everywhere it reappears:

| Grade | Meaning | Home section |
|-------|---------|--------------|
| `documented` | Stated explicitly in Codex's own documentation | `Confirmed Compatible` |
| `inferred` / `unconfirmed` | Not stated in documentation found during this build, or stated as absent; resolvable only by an actual probe run or a documentation lookup this build did not perform | `Unverified / Unknown` (tied to a probe or to FR6b) |
| `documented absence` | Codex's documentation is silent on, or explicitly lacks, an equivalent mechanism | `Confirmed Blocking Or High-Risk` |

Known grading as of this build:

- **`documented`** — the `SKILL.md` + YAML-frontmatter shape; the optional `scripts/` / `references/` / `assets/` subdirectories; global skill discovery at `~/.agents/skills` and repo-local discovery at `.agents/skills`; MCP-server support.
- **`unconfirmed`** — the plugin/extension manifest format; the hooks format; whether Codex's subagent mechanism (if any) accepts an inline prompt and a per-call model override; the absence of a structured mid-task question tool.

### Canonical evidence table

Every quantitative claim anywhere else in this document cites a row below by its command, rather than restating or re-deriving the figure independently. This table is the single durable baseline for this build.

| Command | Value | Date |
|---|---|---|
| `find skills -name SKILL.md \| wc -l` | 38 | 2026-08-03 |
| `find skills -name SKILL.md \| awk -F/ 'NF>3' \| wc -l` | 18 | 2026-08-03 |
| `find skills -name SKILL.md \| awk -F/ 'NF==3' \| wc -l` | 20 | 2026-08-03 |
| `grep -rl CLAUDE_PLUGIN_ROOT skills conventions \| wc -l` | 38 | 2026-08-03 |
| `grep -rl CLAUDE_PLUGIN_ROOT --include=SKILL.md skills \| wc -l` | 37 | 2026-08-03 |
| `comm -23 <(find skills -name SKILL.md \| sort) <(grep -rl CLAUDE_PLUGIN_ROOT --include=SKILL.md skills \| sort)` | `skills/design/gather/SKILL.md` | 2026-08-03 |
| `find skills -name '*.sh' \| wc -l` | 14 | 2026-08-03 |
| `grep -rlE '/bf:' --exclude-dir=.git --exclude-dir=.bf . \| wc -l` | 13 | 2026-08-03 |
| `grep -rlE 'Skill\(["\x27]bf:' --exclude-dir=.git --exclude-dir=.bf . \| wc -l` | 3 | 2026-08-03 |
| `grep -rnE 'Skill\(["\x27]bf:' --exclude-dir=.git --exclude-dir=.bf . \| wc -l` | 5 | 2026-08-03 |
| `grep -rl '\$ARGUMENTS' --include=SKILL.md skills \| wc -l` | 19 | 2026-08-03 |
| `grep -rlE '^name:' --include=SKILL.md skills \| wc -l` | 38 | 2026-08-03 |
| `grep -rlE '^description:' --include=SKILL.md skills \| wc -l` | 38 | 2026-08-03 |
| `grep -rlE '^model:' --include=SKILL.md skills \| wc -l` | 38 | 2026-08-03 |
| `grep -rlE '^disable-model-invocation:' --include=SKILL.md skills \| wc -l` | 35 | 2026-08-03 |
| `grep -rlE '^argument-hint:' --include=SKILL.md skills \| wc -l` | 25 | 2026-08-03 |
| `grep -rlE '^allowed-tools:' --include=SKILL.md skills \| wc -l` | 23 | 2026-08-03 |
| `find skills -type d \( -name references -o -name assets \)` | *(empty)* | 2026-08-03 |
| `git rev-parse HEAD` | `d373524dffd0238ca107f436cbf7869b4a7b8152` | 2026-08-03 |
| `git rev-parse --abbrev-ref HEAD` | `feat/codex-universal-support` | 2026-08-03 |
| `date -u +%F` | `2026-08-03` | 2026-08-03 |

## Confirmed Compatible

These are couplings known-portable on the strength of documented format overlap — all graded `[documented]`.

- **The `SKILL.md` + YAML-frontmatter shape itself, and the required `name`/`description` keys.** `[documented]` Both keys are present in 38/38 `SKILL.md` files (evidence table rows: `grep -rlE '^name:' --include=SKILL.md skills | wc -l` = 38; `grep -rlE '^description:' --include=SKILL.md skills | wc -l` = 38). Codex documents the same `SKILL.md` + frontmatter shape as its skill format.
- **The `skills/<name>/scripts/*.sh` layout.** `[documented]` bf already places its 14 shell scripts (evidence table row: `find skills -name '*.sh' | wc -l` = 14) under per-skill `scripts/` subdirectories, which is the same convention Codex documents. No restructuring is needed for this slice of the format.
- **bf's interactivity model.** `[documented]` "Ask ONE question at a time" is prose instruction in `conventions/plugin-main.md`, not a call to a host-provided structured question tool. Prose read by an agent is portable to any host capable of reading and following markdown — it does not depend on a Claude Code–specific API.
- **Markdown-body instructions generally.** `[documented]` The overwhelming majority of every bf skill's content is prose an agent reads and follows step by step. This is the bulk of the format, and it is host-agnostic by construction — it needs nothing beyond a host that hands an agent a file's text as instructions.
- **Zero use of `references/` or `assets/` directories.** `[documented]` bf uses neither (evidence table row: `find skills -type d \( -name references -o -name assets \)` = empty). This slice of Codex's documented format overlap is therefore untested by this repo but also unneeded — bf carries no risk here because it never exercises the feature.

## Unverified / Unknown

### `${CLAUDE_PLUGIN_ROOT}` — highest blast radius, canonical home

`[unconfirmed]` Is there a Codex equivalent of `${CLAUDE_PLUGIN_ROOT}` — a variable resolving to the extension's own install root? This is unconfirmed by documentation found during this build; probe 2 (`codex-probes/probe-2-plugin-root/bf-probe-pluginroot/SKILL.md`) exists to test it as a discovery exercise, since even the *name* of any Codex equivalent is unknown.

38 files reference `${CLAUDE_PLUGIN_ROOT}` (evidence table row: `grep -rl CLAUDE_PLUGIN_ROOT skills conventions | wc -l` = 38), the highest blast radius of any single item in this document. **Number-framing note:** this 38 coincidentally equals the 38 total `SKILL.md` files, but the two are different sets — do not read it as a copy-paste error. The composition is 37 `SKILL.md` files (evidence table row: `grep -rl CLAUDE_PLUGIN_ROOT --include=SKILL.md skills | wc -l` = 37) plus `conventions/plugin-main.md` = 38. The sole `SKILL.md` that does **not** reference it is `skills/design/gather/SKILL.md` (evidence table row: `comm -23 …` result).

This coupling has two distinct failure surfaces, not one:

- **(a) Convention/sub-skill file reads.** Nearly every `SKILL.md` reads `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` near its top, and orchestrators resolve sub-skills by prepending `${CLAUDE_PLUGIN_ROOT}/skills/` to a path in a routing table.
- **(b) Script invocation.** All 14 shell scripts under `skills/` (evidence table row: `find skills -name '*.sh' | wc -l` = 14) are invoked as `bash "${CLAUDE_PLUGIN_ROOT}/skills/…/x.sh"`. State management (`state-ops.sh`, `init-probe.sh`) sits entirely behind this path — an unset variable here does not degrade gracefully, it breaks state handling outright.

### The orchestration-substrate gap (FR6b) — ranked alongside `${CLAUDE_PLUGIN_ROOT}`, no probe exists

`[unconfirmed]` Does Codex provide a subagent mechanism that accepts an inline prompt **and** a per-call model override? This is bf's actual orchestration substrate: every phase sub-skill is executed by reading its `SKILL.md` from a path, passing the file's contents as an agent prompt, and passing the `model` declared in that file's frontmatter — see `skills/feature/SKILL.md` §Sub-skill Resolution and `skills/micro/SKILL.md` §Sub-skill Resolution, both of which state sub-skills are resolved by reading a file path directly rather than through host skill discovery. The plugin's Parallel Fan-Out convention depends on the same mechanism plus concurrent spawning and agent naming.

- **No probe exists for this in this build**, deliberately. The Codex subagent API shape is unconfirmed by any documentation found during this build, so any probe here would encode a guessed API; its failure would prove nothing about Codex, only about the guess.
- **What would resolve it:** reading Codex's own subagent documentation, or one interactive session with a Codex install.
- This absorbs the shallower observation that 38/38 `SKILL.md` files declare a `model:` key (evidence table row: `grep -rlE '^model:' --include=SKILL.md skills | wc -l` = 38) — "does Codex ignore the `model` key" is subordinate to the real question, "can Codex route a sub-call to a chosen model at all."
- If the answer turns out to be no, bf's workflow still **runs** — it just silently loses per-phase model routing and parallel fan-out. That is a degradation, not an error, and is invisible unless someone explicitly checks for it.

### Nested `SKILL.md` files (18 of 38) — a harmlessness question, not a capability question

`[unconfirmed]` 18 of 38 `SKILL.md` files sit nested below the top level of a skills directory (evidence table row: `find skills -name SKILL.md | awk -F/ 'NF>3' | wc -l` = 18, vs. 20 top-level). This count is given as **context, not exposure** — bf resolves its own sub-skills by file path, not by relying on the host to discover nested skills (see the orchestration-substrate entry above). So the question this build needs answered is not "can Codex find nested skills" but "does anything bad happen if Codex encounters one" — see probe 1 (`codex-probes/probe-1-nested-handling/`), which is framed around a four-outcome observation matrix (spelled out in the Verification Checklist, §7) rather than a single yes/no.

### `$ARGUMENTS` substitution

`[unconfirmed]` Does Codex substitute `$ARGUMENTS` (or an equivalent) with user-supplied invocation arguments? 19 `SKILL.md` files reference the token (evidence table row: `grep -rl '\$ARGUMENTS' --include=SKILL.md skills | wc -l` = 19) — **never 20**: a repo-wide grep returns 20 because `skills/feature/scripts/init-probe.sh:4` contains `# Usage: bash init-probe.sh "$ARGUMENTS"`, a shell-comment usage example, not a host substitution site. See probe 3 (`codex-probes/probe-3-arguments/bf-probe-arguments/SKILL.md`).

### Frontmatter parser tolerance

`[unconfirmed]` Does Codex's frontmatter parser tolerate unknown keys (ignore them) or reject them (error)? See probe 4 (`codex-probes/probe-4-frontmatter/bf-probe-frontmatter/SKILL.md`), which also distinguishes the dangerous third outcome — accepted-and-ignored — from both pass and error.

## Confirmed Blocking Or High-Risk

## Recommendation

## Verification Checklist
