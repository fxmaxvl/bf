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

These are couplings with a `[documented absence]` grade — Codex's documentation, as researched during this build, has no stated equivalent — or a documented behavioural asymmetry that makes silent failure worse than loud failure.

- **Plugin/marketplace manifests.** `[documented absence]` `.claude-plugin/plugin.json` (name `bf`, version `1.26.0`) and `.claude-plugin/marketplace.json` have no confirmed Codex equivalent. The `bf:` namespace that every `/bf:x` reference depends on originates here — without an equivalent manifest concept, there is no `bf:` namespace to resolve against on Codex.
- **The literal `Skill("bf:…")` call form.** `[documented absence]` The 13 files containing `/bf:`-style references (evidence table row: `grep -rlE '/bf:' --exclude-dir=.git --exclude-dir=.bf . | wc -l` = 13) split into two risk levels, not one:
  - *Prose references* (~10 files, e.g. "invoke `/bf:decide`", "see `/bf:scan-conventions`") are natural-language instructions. They degrade gracefully — on a host with no such command, the text is still readable and a capable agent can do the equivalent work by hand. **Low risk.**
  - *Literal `Skill("bf:…")` call sites* — 3 files, 5 sites (evidence table rows: `grep -rlE 'Skill\(["\x27]bf:' --exclude-dir=.git --exclude-dir=.bf . | wc -l` = 3, `grep -rnE 'Skill\(["\x27]bf:' --exclude-dir=.git --exclude-dir=.bf . | wc -l` = 5 — `conventions/plugin-main.md:62`, `skills/design/SKILL.md:242-243`, `skills/gather/SKILL.md:176-177`) are a hard dependency on a host API named `Skill` accepting a `"<plugin>:<skill>"` identifier and an `args` string. No known Codex equivalent. **High risk, but narrow** — all 5 sites are in handoff/terminal paths (`bf:feature`, `bf:quick`, `bf:design`, `bf:adr-writer`).
- **`disable-model-invocation: true` (35 files).** `[documented absence]` (evidence table row: `grep -rlE '^disable-model-invocation:' --include=SKILL.md skills | wc -l` = 35) This is a **silent-wrong-behaviour** risk, not merely an unsupported key. If Codex ignores this key rather than erroring on it, `decide`, `consilium`, and every phase sub-skill become model-invocable and can auto-fire on unrelated prompts. Ignoring the key is worse than failing on it.
- **`allowed-tools` (23 files).** `[documented absence]` (evidence table row: `grep -rlE '^allowed-tools:' --include=SKILL.md skills | wc -l` = 23) A **permission** risk with the same asymmetry as above: if ignored, a skill gets broader tool access than its author declared.

`${CLAUDE_PLUGIN_ROOT}` is **not** restated here — see `${CLAUDE_PLUGIN_ROOT}` under Unverified / Unknown, since whether it ends up blocking depends entirely on the still-open question of whether Codex has an equivalent. The 18-of-38 nested-`SKILL.md` figure and the `model:` frontmatter key are likewise not listed here — both live under Unverified / Unknown, where their risk is framed correctly (harmlessness question and orchestration-substrate gap, respectively).

## Recommendation

**Do not port any real bf skill to Codex yet.** Three reasons:

- **(a) All four mechanical unknowns are unresolved,** two of them with a 20+ file blast radius: `${CLAUDE_PLUGIN_ROOT}` at 38 files (evidence table row: `grep -rl CLAUDE_PLUGIN_ROOT skills conventions | wc -l`), and `disable-model-invocation` frontmatter at 35 files (evidence table row: `grep -rlE '^disable-model-invocation:' --include=SKILL.md skills | wc -l`).
- **(b) The low-coupling skills that look like easy pilots are also the most interaction- and fan-out-heavy** in the repo. A port that appears to work on one of these would not generalise — it would hide exactly the orchestration-substrate risk (FR6b, §4) that matters most, because a "successful" pilot proves nothing about the sub-skills that actually exercise cross-skill invocation and per-call model routing.
- **(c) Two of the highest-risk items fail silently, not loudly** (`disable-model-invocation`, §5; `allowed-tools`, §5). A port cannot be validated by "it ran without error" when the exact failure mode is behaviour being quietly ignored rather than rejected.

**Ordered sequence of work that would be justified once the probes resolve** (see §7 Verification Checklist for how to run each):

1. Run probes 2 and 3 first — resolve whether Codex has a plugin-root equivalent and an `$ARGUMENTS` equivalent. Both are prerequisites for almost anything else bf does.
2. Run probe 4 — resolve frontmatter tolerance, distinguishing accepted-and-ignored from the other two outcomes.
3. Run probe 1 with its full control-and-registry-inspection procedure — resolve nested-`SKILL.md` harmlessness.
4. Read Codex's subagent documentation (or run one interactive session) to resolve the orchestration-substrate gap (FR6b) — this is the item with no probe and the highest strategic weight, since it decides whether bf's per-phase model routing and parallel fan-out are portable at all.
5. Only after all four are resolved: pick the single lowest-risk bf skill that does **not** depend on cross-skill invocation or model routing, and attempt a real port as a pilot — not before.

### Not Investigated

The following topics were deliberately left out of this build's scope and are not covered above:

- **MCP-server configuration portability.** bf itself declares no MCP server, so this was not investigated.
- **Hooks / `.claude/settings*.json` portability.** `.claude/settings.local.json` is user-local and not part of the plugin's shipped surface.
- **A Codex-equivalent plugin manifest.** No documentation research established the manifest format, so writing a speculative one would be invention, not a probe of a specific question.
- **CI enforcement of this document's own word ban** (see NFR1 in the build's spec). A manual grep at build time is sufficient; a lint rule would be over-engineering for one document.

## Verification Checklist

Six numbered entries: one per probe (four), one for the probe-less orchestration-substrate unknown (FR6b), and a final entry recording the Codex CLI version and date. Work top to bottom. All probe files referenced below live under `codex-probes/` — see `codex-probes/README.md` for install instructions.

### 1. Probe 1 — nested `SKILL.md` handling

- **(a) Command(s):** First, as a **mandatory control**, install and run probe 2 or probe 3 (a top-level probe) from the same Codex skills location and confirm it loads — see entries 2/3 below. Only then: copy `codex-probes/probe-1-nested-handling/bf-probe-parent/` (including its `child/` subdirectory) into a Codex skills location (e.g. `~/.agents/skills/bf-probe-parent/`), invoke `bf-probe-parent`, then separately inspect Codex's skill/command registry listing for a child entry, and separately attempt **direct invocation** of the child skill (e.g. `bf-probe-child`, or whatever name the registry shows).
- **(b) Expected output on success:** depends on which of four outcomes occurs (see matrix below) — there is no single "success" string; `BF_PROBE_1_PARENT_LOADED` from the parent is always expected once the control run confirms probes load from this location at all.
- **(c) Failure / outcome matrix:**
  1. Both `BF_PROBE_1_PARENT_LOADED` **and** `BF_PROBE_1_CHILD_LOADED` appear → nested files are loaded and executed.
  2. `BF_PROBE_1_PARENT_LOADED` appears, `BF_PROBE_1_CHILD_LOADED` does not, **and** the child does not appear in Codex's registry listing → silently ignored. **This is a pass** — bf does not need nested skills discovered.
  3. `BF_PROBE_1_PARENT_LOADED` appears, `BF_PROBE_1_CHILD_LOADED` does not, **and** the child does appear in the registry listing → registered but not auto-loaded. Untidy namespace pollution, not blocking — confirm by attempting direct invocation of the child; if that also fails to produce `BF_PROBE_1_CHILD_LOADED`, note that separately.
  4. Neither sentinel appears, plus a load error or refusal → hard failure, the only genuinely blocking outcome. **This outcome is only interpretable given the control from (a)** — without a top-level probe having already loaded successfully from the same location, this cannot be distinguished from "the parent file is malformed" or "Codex loads nothing from this location at all."
- **(d) Section to update:** `Unverified / Unknown` (nested `SKILL.md` entry) and, if outcome 4 occurs, promote the finding to `Confirmed Blocking Or High-Risk`.

### 2. Probe 2 — plugin-root equivalent

- **(a) Command(s):** copy `codex-probes/probe-2-plugin-root/bf-probe-pluginroot/` into a Codex skills location, invoke `bf-probe-pluginroot`.
- **(b) Expected output on success:** a line `BF_PROBE_2_ROOT=<value>` where `<value>` is a real filesystem path.
- **(c) Failure:** `<value>` is an unexpanded literal token (e.g. the string `${CLAUDE_PLUGIN_ROOT}` printed verbatim) rather than a path — this is the negative result, not a crash.
- **(d) Section to update:** `Unverified / Unknown` (`${CLAUDE_PLUGIN_ROOT}` entry) — if a working equivalent is found, also revisit `Confirmed Blocking Or High-Risk` and `Recommendation`, since this is the highest-blast-radius unknown.

### 3. Probe 3 — `$ARGUMENTS` substitution

- **(a) Command(s):** copy `codex-probes/probe-3-arguments/bf-probe-arguments/` into a Codex skills location, invoke e.g. `bf-probe-arguments hello world`.
- **(b) Expected output on success:** a line `BF_PROBE_3_ARGS=hello world` (the actual invocation text substituted in).
- **(c) Failure:** the line shows the literal, unexpanded text `$ARGUMENTS` instead of the invocation text — this is the negative result.
- **(d) Section to update:** `Unverified / Unknown` (`$ARGUMENTS` entry).

### 4. Probe 4 — frontmatter tolerance

- **(a) Command(s):** copy `codex-probes/probe-4-frontmatter/bf-probe-frontmatter/` into a Codex skills location, invoke `bf-probe-frontmatter`.
- **(b) Expected output on success:** `BF_PROBE_4_LOADED`, plus a report of which of the three outcomes below occurred.
- **(c) Failure / outcome (three-way, not two-way):**
  1. Accepted-and-honoured — the four non-standard keys visibly changed behaviour.
  2. **Accepted-and-ignored** — `BF_PROBE_4_LOADED` printed, but none of the four keys had any effect. This is the dangerous silent-failure shape: it looks identical to outcome 1 from the sentinel alone.
  3. Rejected — Codex refuses to load the file or errors before `BF_PROBE_4_LOADED` ever prints.
- **(d) Section to update:** `Confirmed Blocking Or High-Risk` (`disable-model-invocation` and `allowed-tools` entries) if outcome 2 occurs; `Unverified / Unknown` otherwise.

### 5. Orchestration substrate / per-call model override — **no probe — documentation lookup**

- **(a) Action:** read Codex's subagent documentation, and/or run one interactive session with a Codex install attempting to spawn a sub-call with an inline prompt and a specific model.
- **(b) Expected finding on success:** documentation (or an observed session) confirms Codex can accept an inline prompt and route a sub-call to a chosen model.
- **(c) Failure / negative finding:** documentation confirms no such mechanism exists, or is silent on it after a genuine search — record which.
- **(d) Section to update:** `Unverified / Unknown` (orchestration-substrate entry, FR6b) — if the answer is no, also revisit `Recommendation`, since this is the item with the highest strategic weight.

### 6. Record Codex CLI version and date

- **(a) Action:** record the exact Codex CLI version string (e.g. `codex --version` or equivalent) and the date every entry above was actually run.
- **(b) Expected output:** a version string and an ISO date, recorded alongside the results of entries 1–5.
- **(c) Failure:** no version could be determined — record that fact explicitly rather than omitting the field.
- **(d) Section to update:** `How This Was Determined` (append a "results recorded" note) — this exists because Codex's extension model is young and answers may not survive a release; a stale, unrecorded version silently invalidates every other entry above it.
