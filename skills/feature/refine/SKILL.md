---
name: refine
description: Lightweight Q&A to clarify scope and approach for quick-mode features. Produces a Q&A file that feeds directly into planning.
model: sonnet
disable-model-invocation: true
argument-hint: [idea description]
---

Ask the user 2-5 focused questions to clarify scope and approach for a small change. This is the quick-mode alternative to the full brainstorm — no spec is generated, the Q&A feeds directly into the plan phase.

## Questions to ask

Ask questions one at a time, building on previous answers. Focus on:

1. **Scope boundaries** — What exactly should change? What should NOT change?
2. **Edge cases** — Are there tricky scenarios to handle?
3. **Approach** — Do you have a preferred implementation approach, or should I decide?
4. **Acceptance criteria** — How will we know this is done?

## Knowing when to stop

Stop early if:
- The idea is already clear and well-scoped (e.g., "fix the typo in X" needs 0-1 questions)
- The user confirms they've covered everything
- You have enough to produce a focused plan

Aim for 2-5 questions. Fewer is better if the idea is straightforward. Do **not** over-question small, obvious changes.

## Output

Once you have enough information, run the helper script to get state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"
```

Save a Q&A summary to the path at `paths.qa`. Format:

```markdown
# Refine Q&A

## Original Idea
<original idea text>

## Clarifications
**Q: <question>**
A: <answer>

**Q: <question>**
A: <answer>
```

Do **not** generate a spec or plan — that is handled by the plan phase.

Here is the idea:
$ARGUMENTS
