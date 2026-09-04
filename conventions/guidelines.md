# Engineering Guidelines

Behavioral guardrails against the failure modes LLM coding assistants fall into most often:
overcomplication, hidden assumptions, vague success criteria — and bolt-on changes that leave the
code they touch incoherent.

Adapted from [Andrej Karpathy's observations on LLM coding pitfalls](https://x.com/karpathy/status/2015883857489522876) (MIT-licensed source: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)).
**Sections 2 and 3 diverge deliberately from that source.** Its strict surgical-change rule —
every changed line must trace to the request, never refactor what isn't broken — reliably produced
changes that were technically minimal and practically wrong: new behavior stapled onto a method
without asking whether the method still made sense afterwards. Sections 2 and 3 below keep the
anti-sprawl intent and replace the line-tracing test with a coherence test.

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

Measure simplicity against **the code you leave behind, not the size of your diff.** A five-line
addition that leaves a method doing three unrelated things is not the simple option — it is the
lazy one, and it has moved the complexity from your diff into the codebase. Sometimes the simplest
end state costs a larger change than the smallest possible one.

The test: *would a senior engineer call the resulting code overcomplicated?* If yes, simplify
before handing it over. The same test applies when reviewing someone else's change: where a
simpler solution exists, recommend it even if what's there is technically correct.

## 3. Coherent Changes

**Assess wide. Change narrowly. Leave the code making sense.**

### Assess at feature-slice radius

Before and after editing, look at the **feature slice**: every file your change touches plus
their direct collaborators — the full call path of the behavior you are changing. Not the whole
repo, and not just the lines you typed.

After adding to an existing unit, re-read **the whole unit** and check it against every breakage
kind in the table below. State the result; "I re-read it and it still reads as one coherent thing"
is a valid answer, silence is not.

Anything the table catches is a finding. Never skip this because the addition was small — small
additions to load-bearing methods are exactly where incoherence accumulates.

### What counts as broken

"Broken" is not only *behaviorally* broken. Design-level breakage counts, and it is the kind an
assistant is most likely to wave through because the tests still pass:

| Kind | It is broken when |
|------|-------------------|
| **Behavior** | Wrong output, a crash, a failing or newly-meaningless test. |
| **Abstraction** | The unit now leaks a concern from another layer, or its callers must know its internals to use it correctly. A flag parameter threaded through to select between two behaviors is the usual tell. |
| **Encapsulation** | State or an invariant is now reachable or mutable from outside the type that owns it, or an invariant is enforced at the call site instead of inside the owner. |
| **Contract** | The name, signature, type, or doc comment no longer describes what the code does — or existing callers silently get different behavior than before. |
| **Readability** | The unit can no longer be followed in one read: nesting deepened, levels of abstraction mixed, or a comment is now needed to explain what the code itself should say. |
| **Consistency** | The slice now solves one problem two different ways, or the same concept goes by two names. |
| **Cohesion** | The unit acquired a second responsibility, or the logic landed in the file that was convenient rather than the file that owns it. |

Two rules bound this, and they do the real work:

- **Judge the end state, not the diff.** Ask what these look like *after* your change, not whether
  your lines caused them in isolation. Tests passing is not evidence of none of them.
- **You own what you break or worsen.** Breakage your change introduces — or measurably deepens —
  is yours to fix. Breakage that was already there and that your change neither touches nor
  worsens is a finding to report, not a licence to rewrite. Encountering bad code is not the same
  as being made responsible for it.

### Change only what coherence requires

A finding does not automatically license an edit. Two cases, and the boundary is not a judgment
call to be made loosely:

- **Refactor inline** when your change leaves any of the breakage kinds above in place — split
  the method that now does two things, use the helper you were about to duplicate, move the logic
  to the layer that owns it, rename what your change made a lie, restore the invariant to its
  owner. This is in scope, expected, and does not need permission.
- **Write it down** for everything else — pre-existing breakage your change does not worsen, and
  code that is merely ugly, dated, or not how you would have written it. Report it; do not fix it.
  Pre-existing dead code is in this bucket: mention it, don't delete it.

Also still true:

- Match existing style, even where you'd do it differently.
- Remove imports, variables, and functions that **your** change made unused.
- Don't reformat, re-comment, or tidy code you had no reason to open.

The test: **does my change make sense where it lands?** Every changed line must be defensible as
either the request itself or what the request made necessary — where "necessary" means it fixes
breakage your change would otherwise have introduced. A line you cannot defend either way
is a line to revert.

When a coherence refactor makes the diff substantially larger than the request implies, say so in
your report: what you refactored, and which finding forced it. A larger diff is acceptable; an
unexplained one is not.

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
