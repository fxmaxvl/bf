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

## Confirmed Blocking Or High-Risk

## Recommendation

## Verification Checklist
