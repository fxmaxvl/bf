---
name: bfeature-design-gather
description: Inline Q&A sub-skill that collects design requirements through structured questions. Returns a structured Q&A list to the orchestrator — never writes files itself.
disable-model-invocation: true
model: opus
argument-hint: [idea description]
---

**Hard rule — one question per turn:** Ask exactly one question, then stop and wait for the answer. Never batch two or more questions in a single response, even when transitioning between topic areas.

Gather design requirements by asking the user one question at a time.

## Conventions

Before asking questions, check whether any of the following convention files apply to the design space described in `$ARGUMENTS`. Read any that are relevant — they inform what questions are worth asking and what constraints to surface.

Use `Glob("~/.claude/conventions/*.md")` to find available files. Relevant conventions to consider:

- `architecture.md` — if the idea involves system boundaries, service decomposition, or data ownership
- `dev.md` — if the idea implies implementation decisions (languages, patterns, testing)
- `typescript.md` — if the idea involves TypeScript/JavaScript services

Do not read all conventions blindly — use judgment. If the idea is purely infrastructure, skip `dev.md`. If it is a generic process design, skip `typescript.md`.

## Input

The design idea arrives as `$ARGUMENTS`. If `$ARGUMENTS` is empty or whitespace-only, make the first question: "What do you want to design?"

Otherwise, use `$ARGUMENTS` as the idea and begin with the first question below.

## Questions

Ask 6–8 questions in the order that makes sense for the specific idea. The list below gives the topic areas and their purpose — adapt the phrasing to the actual idea. Stop earlier if the design space is clearly well-defined and further questions would be splitting hairs.

Suggested areas, in rough order:

1. **Problem framing / actors** — Who uses this? What problem are they facing today? Who else is affected?
2. **Systems and services involved** — Which existing services, APIs, databases, or third-party integrations are in scope?
3. **Data flow** — How does data move through the system? What are the inputs and outputs of the key operations?
4. **Trust / security boundaries** — Where does authentication or authorization apply? What data is sensitive?
5. **Failure modes** — What happens when a dependency is down or a request times out? Is partial failure acceptable?
6. **Alternatives considered** — What other approaches were thought of and why were they ruled out (or not yet ruled out)?
7. **Constraints** — Any non-negotiables: performance SLAs, team size, tech stack decisions already locked in?
8. **Success criteria** — How will we know the design worked? What does done look like?

## Cancellation

If the user sends an empty reply, types `/cancel`, or otherwise signals they want to stop, immediately cease asking questions and return the following cancellation signal to the orchestrator (do not write any file):

```
BFEATURE_DESIGN_CANCELLED
```

## Output

This sub-skill does NOT write any file. Once you have gathered enough answers (or the user signals they are done), return a structured list of Q&A pairs to the orchestrator in this format:

```
BFEATURE_DESIGN_QA_COMPLETE

Original Idea: <idea text>

Q: <question 1>
A: <answer 1>

Q: <question 2>
A: <answer 2>

...
```

The orchestrator reads this output and writes the temp file to `/tmp/bfeature-design-qa-<timestamp>.md`. Do not attempt to write to that path yourself.

Here is the idea:
$ARGUMENTS
