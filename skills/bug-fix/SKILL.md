---
name: bug-fix
description: Use when reporting a bug, debugging a regression, or asking to fix broken behavior given symptoms. Runs an autonomous root-cause → solution → plan → execute flow with decide gates between every phase.
model: opus
disable-model-invocation: false
argument-hint: "[bug symptoms + any directions, e.g. 'login redirects loop after 401 — check refresh-token path']"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Autonomous bug-fix workflow. The user provides symptoms + directions and grants all permissions upfront. The skill then runs Investigate → Diagnose → Design → Plan → Execute without further user input. Every phase boundary is gated by the **decide** skill — no human approval points.

## On Invocation

1. Capture `$ARGUMENTS` as the **symptoms brief**. Do not ask the user to expand on it — decide resolves ambiguity.
2. Resolve repo root: `git rev-parse --show-toplevel`.
3. Create session log at `$repo_root/.bf/sessions/<timestamp>-bug-fix-session-log.md` with blocks `## Symptoms`, `## Hypotheses`, `## Root Cause`, `## Solutions`, `## Plan`, `## Decisions`, `## Execution`.
4. Write the symptoms brief into `## Symptoms`.
5. Print banner (plain text):

```
── bf:bug-fix ─────────────────────────────────────────────
```

## Phase 1 — Investigate (parallel hypothesis hunt)

Spawn **3 named Agent subagents in parallel** per the **Parallel Fan-Out** convention in `plugin-main.md` (single message, three Agent tool calls, `subagent_type: general-purpose`), named so they show on the fleet board. They run independently and must not message each other — their value is uncorrelated angles on the same bug. Each agent gets the symptoms brief and an angle:

- **`recent-change` (Agent A)**: grep `git log -p --since="14 days"` and the diff of likely files for changes that match the symptom area; return ranked candidate root causes with file:line citations.
- **`code-path` (Agent B)**: trace the failing behavior from entry point to suspected fault site; return the call chain and the most-suspect node with file:line.
- **`data-state` (Agent C)**: examine inputs, persisted state, config, env, and external boundaries (API, DB) that could produce the symptom; return ranked candidates with citations.

Each agent must return **under 250 words**, with concrete file:line citations and a confidence (high/medium/low) per hypothesis.

Append all three reports to `## Hypotheses` in the session log.

## Phase 2 — Diagnose (decide picks the root cause)

Invoke decide inline. Read `${CLAUDE_PLUGIN_ROOT}/skills/decide/SKILL.md`.

Payload:
```
QUESTION: Which hypothesis is the actual root cause of the reported symptoms?
PHASE: Diagnose
SESSION_LOG: <absolute path>
OPTIONS: <enumerate the distinct hypotheses from Phase 1 — typically 2–4>
CONTEXT:
<symptoms brief + the strongest evidence excerpt from each agent's report, with file:line citations>
```

Write the verdict to `## Root Cause`. If decide returns confidence `low`, log the flag and proceed — do not stop.

## Phase 3 — Design (architect proposes solutions)

Acting as architect, propose **2–3 distinct solutions** for the root cause from Phase 2. Each solution must include:

- **Approach**: 1-paragraph description.
- **Files touched**: list of paths.
- **Tradeoffs**: scope, reversibility, risk of regression, alignment with `architecture` and `dev` conventions (resolve via the lookup in `plugin-main.md`).
- **Test impact**: what tests need to change or be added (consult `testing` convention).

Write all proposals to `## Solutions`.

## Phase 4 — Pick (decide selects the best solution)

Invoke decide inline.

Payload:
```
QUESTION: Which proposed solution best fixes the root cause given bf conventions and the codebase?
PHASE: Design-pick
SESSION_LOG: <absolute path>
OPTIONS: <the 2–3 proposals from Phase 3>
CONTEXT:
<root-cause block + concise excerpt of each proposal's approach + tradeoffs>
```

Mark the chosen solution in `## Solutions` with `**CHOSEN**`. Log the verdict to `## Decisions`.

## Phase 5 — Plan (build implementation plan)

Build a stepwise implementation plan for the chosen solution. Each step:

- Files + diff intent (what changes, not how the code looks)
- Test coverage for the step
- Ordering constraint (what must precede it)

Write the plan to `## Plan`.

## Phase 6 — Plan review (decide gate)

Invoke decide inline.

Payload:
```
QUESTION: Is the plan complete, ordered correctly, and free of scope creep relative to the chosen solution?
PHASE: Plan-review
SESSION_LOG: <absolute path>
OPTIONS: A) Approve and execute as-is.  B) Revise the plan (decide specifies what must change).
CONTEXT:
<chosen-solution excerpt + full plan>
```

If verdict is B: apply decide's specified revisions to the plan and re-invoke decide on the revised plan. After **2** failed revision rounds, log a low-confidence flag in `## Decisions` and execute the latest plan anyway (per autopilot doctrine: do not stop, do not wait).

## Phase 7 — Execute

Follow the approved plan step by step. For each step:

1. Apply code changes (consult `dev` and `typescript` conventions via the plugin-main lookup).
2. Add or update tests (consult `testing`).
3. Run the project's test command (detect via existing repo conventions — `package.json` scripts, `Makefile`, `pyproject.toml`, etc.).
4. Append a short status line to `## Execution` (step N: pass/fail + key evidence).

If a test fails: do **not** ask the user. Diagnose and re-attempt. After 2 failed attempts on the same step, invoke decide with a `QUESTION: How to proceed given the failing step?` payload and follow its verdict.

## Phase 8 — Finalize

When all steps pass:

1. Re-run the full test suite once for safety.
2. **ADR check:** apply the **ADR Awareness** convention from `plugin-main.md` against this session's changed files/decisions, with one adjustment — this skill never prompts the user interactively (per its autonomous design). If an ADR looks affected, do **not** invoke `bf:adr-writer` automatically; instead surface it as an `ADR flag` in the summary below so the user can decide whether to run it.
3. Write a `## Summary` block: root cause (1 line), fix (1 line), files changed, tests added.
4. Print:

```
── bf:bug-fix | Done ──────────────────────────────────────

Root cause: <one-liner>
Fix: <one-liner>
Files changed: <count>
Low-confidence flags: <list, or "none">
ADR flags: <affected ADR(s) with path + title, or "none">
Session log: <absolute path>
```

Do not commit unless the invoking caller (autopilot, user) explicitly requested it.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Symptoms brief is one sentence with no citation surface | Phase 1 agents still run; Agent A leans on broad `git log` scan. Critic in Phase 2 may flag `low` — proceed. |
| All three Phase-1 agents return the same hypothesis | Skip decide enumeration; record the hypothesis as `## Root Cause` directly with a note. |
| Repo has no test command discoverable | Skip step 3 of execution; flag in `## Decisions` and continue. Final summary surfaces the flag. |
| Chosen solution touches files outside the repo or requires destructive actions | Stop execution, log a `STOP` decision, and print a clear handoff asking the user to authorize. This is the one phase where autonomy yields to safety. |
| Critic returns verdict B on plan review twice in a row | Execute the latest plan anyway and log a low-confidence flag (per autopilot doctrine). |
| Phase-1 agent fails to return | Treat its slot as empty; proceed with the remaining hypotheses. Critic still picks. |
