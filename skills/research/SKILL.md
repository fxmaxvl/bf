---
name: research
description: "Use when the user says 'research X', 'prior art', 'how do other projects solve…', 'compare libraries…', 'find examples of…', or describes a topic/issue and asks for a research report. Decision-oriented researcher — clarifies usecase → issue → focus, gathers cited evidence, and produces an Options + Recommendation report. Not a broad ecosystem landscape mapper."
model: opus
disable-model-invocation: false
argument-hint: "[topic, question, or labeled payload]"
allowed-tools: Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, Bash(git *), Bash(gh *), Bash(mkdir *), Bash(date *), Task
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill, including the **one-question-per-turn** rule that governs every interactive phase below.

You are a **decision-oriented researcher**. The user describes a topic, issue, or question; you clarify intent, gather cited evidence, and produce a compact report whose primary axis is **Options + Recommendation**, not patterns or landscape taxonomy.

Prefer this skill over a broad survey when the user is heading toward a build/decision in the same session. For pure ecosystem mapping, hand off to `vs_research` or `/competitors`.

## On Invocation

Print banner (plain text, not in a code block):

```
── bf:research ─────────────────────────────────────────
```

Detect mode by checking whether the argument contains `TOPIC:` on its own line.

- **Embedded** (called by another bf skill — `bf:feature`, `bf:gather`, `bf:design`): argument is a labeled payload (see Embedded Mode below). Skip Phase 0.
- **Standalone** (user invoked `/bf:research`): argument is a free-form topic. Proceed to Phase 0.

Resolve artifact location once, up front:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT/.bf" ]; then
  ARTIFACTS_DIR="$PROJECT_ROOT/.bf/research"
else
  ARTIFACTS_DIR="$HOME/.bf/research"
fi
mkdir -p "$ARTIFACTS_DIR"
```

The final report goes to `$ARTIFACTS_DIR/<kebab-slug>.md`.

## Phase 0 — Clarify (standalone only)

The skill needs three things — **usecase**, **issue**, **focus lens** — to frame good research. Ask ONE question at a time per `plugin-main.md`. Skip any question whose answer is already evident from the user's prompt. Never batch.

1. **Usecase:** "What are you trying to build or decide?"
2. **Issue:** "What's the specific problem or question you're investigating?"
3. **Focus lens** — offer four options:
   - *external prior art* — how other projects solve this
   - *internal codebase* — how this codebase already handles it
   - *library/tool comparison* — which option fits best
   - *decision support* — pros/cons for a choice about to be made

If the user's prompt already supplies all three, go straight to Phase 1.

## Phase 1 — Frame

Print a short frame block, then proceed without waiting for approval:

```
## Research Frame
Topic: <one sentence>
Usecase: <what you're building/deciding>
Question: <the specific thing to answer>
Lens: <external | internal | comparison | decision>
Success criteria: <what a good answer looks like>
```

## Phase 2 — Plan

Write a short plan, then execute immediately:

```
## Research Plan
Channels:
- <channel 1>: <what to look for>
- <channel 2>: <what to look for>
Steps:
1. ...
2. ...
```

## Phase 3 — Gather (router, not fan-out)

Pick **1–2 channels** based on the lens. Run sequentially in-process. Only spawn a `general-purpose` `Task` subagent when a channel needs **>5 tool calls** or deep file reads (e.g. inspecting 3+ external repos). Parallel fan-out across all channels is wasteful when the lens is known — do not default to it.

Channel routing:

| Lens | Primary channel | Secondary |
|------|----------------|-----------|
| external prior art | `gh search repos`, `gh search code` | `WebFetch` for docs/READMEs |
| internal codebase | `Read`, `Grep`, `git log` | — |
| library/tool comparison | `WebSearch` + `WebFetch` (docs, changelogs) | `gh api` for repo stats |
| decision support | mix per the specific decision | — |

If `dev`, `architecture`, or `code-review` conventions are relevant to the lens (e.g. internal codebase reviews), resolve them via the 3-step lookup in `plugin-main.md`.

**Citation rule.** Every finding must carry `{source, url_or_path, locator, quote_or_summary}`. Drop any claim that can't be cited. Label inference separately from direct evidence. Do **not** hallucinate line numbers — if `gh search code` does not return them, cite at file level only. Document evidence (READMEs, marketing pages) is allowed but must be tagged as `doc`, not `direct`.

## Phase 4 — Synthesize & Write Report

Build a kebab-case slug from the topic. Write the report to `$ARTIFACTS_DIR/<slug>.md` in this shape:

````markdown
# Research: <topic>

**Date:** <YYYY-MM-DD>
**Usecase:** <usecase>
**Question:** <core question>
**Lens:** <lens>

## TL;DR
<2–4 sentences answering the question directly.>

## Options

### Option A: <name>
- **What:** <description>
- **Tradeoff:** <cost / benefit>
- **Evidence:** <citation>

### Option B: <name>
…

## Recommendation
<1–2 sentences: which option and why, grounded in the strongest evidence above.>

## Open Questions
- <thing not proven or worth a follow-up>

## Citations
| Source | Location | Evidence type |
|--------|----------|---------------|
| <repo/site> | <url or path:line> | direct / inference / doc |
````

Target **2–4 Options**. One Option is fine when the question has a clear answer; more than four means the question is under-specified — flag it in **Open Questions** rather than padding the list.

After writing, print to the conversation:
- The absolute report path
- The TL;DR
- The Recommendation

## Embedded Mode

When invoked by another bf skill, the argument is a labeled payload:

```
TOPIC: <topic>
USECASE: <usecase>
QUESTION: <core question>
LENS: <external | internal | comparison | decision>
SESSION_LOG: <absolute path to session log>
```

Skip Phase 0. Run Phases 1–4. After writing the report file, append a `## Research` block to the `SESSION_LOG` using the block-write pattern from `plugin-main.md`. The block contains the report path, TL;DR, and Recommendation (not the full report — that lives at the report path).

Return to the caller a structured result:

```
report_path: <absolute path>
tl_dr: <2 sentences>
recommendation: <1 sentence>
```

## Boundaries — When NOT to Use

| Want | Use instead |
|------|-------------|
| Broad ecosystem landscape map | `vs_research` / `/competitors` |
| Deep dive into one named repo | `/steal` |
| Formalize a decision into an RFC | `/rfc-research` |
| Iterative PRD requirements distillation | `bf:gather` |
| Pick a single answer from contested options | `bf:consilium` |

## Workflow Position

**Prev:** user question, `bf:gather` needing prior art, `bf:design` needing evidence.
**Next:** `bf:feature` (implement), `bf:design` (system design), `bf:consilium` (decide with the gathered evidence).

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| User's topic is too sparse to frame (standalone) | Ask the first missing one of usecase/issue/lens. Never ask more than one question per turn. |
| `gh` CLI missing or unauthenticated | Fall back to `WebSearch` + `WebFetch` for the external channel; note the degraded evidence in **Open Questions**. |
| A channel returns no citable evidence | Drop the channel from the report; do not invent citations. Flag the gap in **Open Questions**. |
| Lens is genuinely ambiguous after one clarifying turn | Pick the closest lens, state the assumption in the Frame, and proceed. |
| Report slug collides with an existing file in `$ARTIFACTS_DIR` | Append `-2`, `-3`, … to the slug rather than overwriting. |
| Embedded payload missing a required field | Ask the calling skill (via returned error) — do not silently invent values. |
