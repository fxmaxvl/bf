---
name: review-impl-analyze
description: Review implementation against spec and plan for completeness and quality. Produces a structured PASS/CONCERN report file.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git *)
model: opus
---

Run the helper scripts to load state and detect changed files:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/full/scripts/state-ops.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/full/scripts/changed-packages.sh"
```

`state-ops.sh` gives you `slug`, `build_timestamp`, `mode`, and `paths.*`.
`changed-packages.sh` gives you `changed_files` — use this to scope the review to what this feature actually changed.

Review the implementation by comparing what was built against the plan and requirements.

## Mode-aware input

- **Full mode** (`mode` = `"full"`): Compare against `paths.spec` and `paths.plan`.
- **Quick mode** (`mode` = `"quick"`): No spec file was generated (quick mode skips brainstorm). Compare against `paths.qa` and `paths.plan`.

## Review Criteria

### 1. Feature completeness
- Read the spec and list every functional requirement
- For each requirement, verify it is implemented by checking the actual code
- Flag any requirement that is missing or partially implemented

### 2. Dev conventions
- Check against the project's `${CLAUDE_PLUGIN_ROOT}/conventions/dev.md` conventions:
  - Code style matches surrounding code
  - No unrelated changes
  - No mock implementations
  - No `--no-verify` in any commits
  - Comments are evergreen (no temporal references)

### 3. Test coverage
- Check against `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md` conventions:
  - Unit tests exist for new functionality
  - Integration tests exist
  - End-to-end tests exist
  - Test output is pristine (no unexpected warnings/errors)

Do **not** run the test suite — `verify` already ran it before this phase. If tests need re-running (e.g., after `review-impl/fix`), the silent verify in finalize handles that.

### 4. Code style
- Naming is evergreen (no "new", "improved", "enhanced")
- Code is simple and readable over clever
- No orphaned or dead code

## Output

Save a report to the path at `paths.impl_report`.

If all criteria pass:

```markdown
# Implementation Review Report
STATUS: PASS
```

If any criterion has concerns:

```markdown
# Implementation Review Report
STATUS: CONCERN

## Concerns

### <Criterion name>
- <file path>:<line> — <specific concern and what needs to change>
- <file path>:<line> — <specific concern and what needs to change>

### <Criterion name>
- <specific concern>
```

Do **not** ask the user any questions and do **not** modify any files — the orchestrator handles that.
