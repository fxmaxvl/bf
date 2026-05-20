---
name: review-design
description: Analyze a feature spec for architecture completeness, edge cases, and requirements. Produces a structured PASS/CONCERN report file.
disable-model-invocation: true
model: opus
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper script to load state and artifact paths:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"
```

This gives you `slug`, `build_timestamp`, and `paths.*`.

Extract the `## Spec` block from `paths.spec` (= `paths.session_log`) using the Block Reading Pattern from `plugin-main.md` and review it against the criteria below.

If `paths.qa` (= `paths.temp`) exists, also extract the `## QA` block and use it to check that the spec faithfully represents what the user said during brainstorm — flag any requirements mentioned in the Q&A that are missing or misrepresented in the spec.

## Review Criteria

### 0. Q&A faithfulness (if `paths.temp` exists)
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

Append a report to `paths.design_report` (= `paths.temp`) using `paths.block_design_report` (`## Design Report`) as the block header. Follow the Block Writing Pattern from `plugin-main.md`.

If all criteria pass:

```markdown
## Design Report

STATUS: PASS
```

If any criterion has concerns:

```markdown
## Design Report

STATUS: CONCERN

### Concerns

#### <Criterion name>
- <specific concern and suggested fix>

#### <Criterion name>
- <specific concern and suggested fix>
```

Do **not** ask the user any questions and do **not** modify the spec — the orchestrator handles that.
