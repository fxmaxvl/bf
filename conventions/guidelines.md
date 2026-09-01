# Engineering Guidelines

Behavioral guardrails against the failure modes LLM coding assistants fall into most often:
overcomplication, collateral edits, hidden assumptions, and vague success criteria.

Adapted from [Andrej Karpathy's observations on LLM coding pitfalls](https://x.com/karpathy/status/2015883857489522876) (MIT-licensed source: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)).

**Scope.** These apply to every skill in this plugin, at every phase. Sections 1 and 4 are
workflow-wide; sections 2 and 3 apply whenever code is being written or modified.

**Tradeoff.** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

---

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick one silently. Lay the readings
  out, then ask which one applies. Presenting options is not the same as batching questions —
  ask **one question at a time**: a single question offering N readings is correct, N separate
  questions in one turn is not.
- If a simpler approach exists, say so. Push back when warranted — citing something real (a
  file and line, a stated rule, an explicit preference), not as reflex. If nothing contradicts
  the claim, accept it and move on; don't manufacture doubt.
- If something is unclear, stop. Name what is confusing, specifically. Ask.

Silent guessing is the expensive failure here: a wrong assumption surfaces after the work is
built, not before.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for scenarios that cannot occur.
- If you wrote 200 lines and it could be 50, rewrite it.

The test: *would a senior engineer call this overcomplicated?* If yes, simplify before handing
it over. The same test applies when reviewing someone else's change: where a simpler solution
exists, recommend it even if what's there is technically correct.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even where you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it. Something worth fixing that
  is outside the current task gets written down, not fixed inline.

When your changes create orphans:

- Remove imports, variables, and functions that **your** change made unused.
- Do not remove pre-existing dead code unless asked.

The test: **every changed line should trace directly to the request.** A line you cannot trace
is a line to revert.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Restate the task as something checkable before starting:

- "Add validation" → "write tests for invalid inputs, then make them pass"
- "Fix the bug" → "write a test that reproduces it, then make it pass"
- "Refactor X" → "tests pass before and after, behavior unchanged"

For any multi-step task, state the plan with a verification check per step:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong criteria let you run independently to completion. Weak criteria ("make it work") force
you back to the user at every step — and let you declare done on work that isn't.

Report against the criteria you stated. If a check fails, say so with the output; do not report
completion on an unverified step.
