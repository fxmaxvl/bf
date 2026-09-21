---
name: discuss
description: Thoughtful Q&A dialogue about a question or topic. Use when the user wants to explore an idea before jumping to solutions.
disable-model-invocation: true
argument-hint: [question or topic]
model: opus
allowed-tools: Read, Grep, Glob
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

On invocation, print this banner as plain text (not in a code block) before doing any other work:

```
── bf:discuss ──────────────────────────────────────────
```

You are given a question or topic to discuss: $ARGUMENTS

Before providing any solution or answer:

1. **Think deeply** about the question - consider different angles, assumptions, and implications
2. **Ask clarifying questions** to better understand:
   - The context and constraints
   - The user's goals and priorities
   - Any assumptions that need validation
   - Edge cases or specific scenarios to consider

3. **Do not jump to conclusions** - engage in a dialogue to ensure you fully understand the problem before proposing solutions

Start by acknowledging the topic and asking one thoughtful clarifying question. Ask follow-up questions one at a time — wait for the user's response before asking the next.

## How to handle answers

When the user gives an answer or takes a position:

### 1. Verify before accepting / Challenge only when warranted

Read `${CLAUDE_PLUGIN_ROOT}/conventions/verification.md` — the verify-before-accepting and challenge-only-when-warranted rules there apply in full.

### 3. Project consequences

Once a direction is agreed upon, think through its downstream effects before moving on:
- What other files, skills, or flows depend on what's being changed?
- Does this create inconsistency anywhere else?
- Are there follow-up changes that will be required?
- Does this affect behavior in edge cases (e.g., quick mode vs full mode, monorepo vs single package)?

Surface these consequences explicitly — e.g., "If we go this route, it also means X and Y will need to change" — and invite the user to discuss them. This is not a blocker, just a heads-up so nothing is a surprise later.

### 4. One thing at a time

Still ask only one question per turn. When projecting consequences, pick the most significant one and raise it first — don't dump a list.


---

## Edge Cases & Errors

| Condition | Handling |
|---|---|
| The topic is too vague to discuss | Ask **one** clarifying question. If the answer is still too thin, say what is missing and stop rather than speculating. |
| The user ends the discussion without settling anything | Capture it as an open question in the closing summary, explicitly marked unresolved. Never record a resolution that was not reached. |
| The discussion resolves something that contradicts a recorded ADR | Say so in one line and point at the ADR. Do not amend it here — that is `bf:adr-writer`'s job. |
| Not in a git repository | The discussion still runs; note that no session artifact can be written and keep the outcome in the conversation. |
| The user asks for implementation mid-discussion | This skill does not write code. Name the workflow that should take it (`bf:micro`, `bf:quick`, `bf:feature`) and stop. |
