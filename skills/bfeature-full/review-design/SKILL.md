---
name: review-design-analyze
description: Analyze a feature spec for architecture completeness, edge cases, and requirements. Produces a structured PASS/CONCERN report file.
disable-model-invocation: true
model: opus
---

Run the helper script to load state and artifact paths:

```
bash ~/.claude/skills/bfeature-full/scripts/state-ops.sh
```

This gives you `slug`, `build_timestamp`, and `paths.*` — use `paths.spec`, `paths.qa`, `paths.design_report` directly.

Review the file at `paths.spec` against the criteria below.

If the file at `paths.qa` exists, read it as well — use it to check that the spec faithfully represents what the user said during brainstorm, and flag any requirements that were mentioned in the Q&A but are missing or misrepresented in the spec.

## Review Criteria

### 0. Q&A faithfulness (if `<build_timestamp>-<slug>-qa.md` exists)
- Does the spec reflect what the user actually said during brainstorm?
- Are there constraints or requirements from the Q&A answers that didn't make it into the spec?

### 1. Architecture completeness
- Are all major components identified?
- Are the boundaries between components clear?
- Are external dependencies and integrations specified?

### 2. Cases and edge cases
- Is the happy path clearly described?
- Are error cases and failure modes covered?
- Are boundary conditions addressed (empty inputs, large inputs, concurrent access, etc.)?

### 3. Requirements completeness
- Are all functional requirements specified with enough detail to implement?
- Are non-functional requirements addressed (performance, security, accessibility)?
- Are there ambiguities or unstated assumptions?

## Output

Save a report to the path at `paths.design_report`.

If all criteria pass:

```markdown
# Design Review Report
STATUS: PASS
```

If any criterion has concerns:

```markdown
# Design Review Report
STATUS: CONCERN

## Concerns

### <Criterion name>
- <specific concern and suggested fix>
- <specific concern and suggested fix>

### <Criterion name>
- <specific concern and suggested fix>
```

Do **not** ask the user any questions and do **not** modify the spec — the orchestrator handles that.
