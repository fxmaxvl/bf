---
name: review-impl
description: Review implementation against spec and plan for completeness and quality. Produces a structured PASS/CONCERN report file.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git *)
model: opus
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper scripts to load state and detect changed files:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/changed-packages.sh"
```

`state-ops.sh` gives you `slug`, `build_timestamp`, `mode`, and `paths.*`.
`changed-packages.sh` gives you `changed_files` — use this to scope the review to what this feature actually changed.

Review the implementation by comparing what was built against the plan and requirements.

## Mode-aware input

- **Full mode** (`mode` = `"full"`): Compare against the `## Spec` block in `paths.spec` (= `paths.session_log`) and the `## Plan` block in `paths.plan` (= same file).
- **Quick mode** (`mode` = `"quick"`): No spec exists. Compare against the `## QA` block in `paths.qa` (= `paths.temp`) and the `## Plan` block in `paths.plan`.

Use the Block Reading Pattern from `plugin-main.md` to extract each block.

## Review Criteria

### 1. Feature completeness
- The spec's `## Functional Requirements` section is the authoritative list. Locate it within the `## Spec` block in `paths.session_log`:
  1. Grep `paths.session_log` for `^## Functional Requirements` to find the start line
  2. Grep `paths.session_log` for the next `^## ` after that line to find the end
  3. Read `paths.session_log` with `offset=<start>` and `limit=<end - start>`
- For each requirement in that section, verify it is implemented by checking the actual code
- Flag any requirement that is missing or partially implemented

### 2. Dev conventions
- Check against the `dev` convention (resolved via the lookup in `plugin-main.md`):
  - Code style matches surrounding code
  - No unrelated changes
  - No mock implementations
  - No `--no-verify` in any commits
  - Comments are evergreen (no temporal references)

### 3. Test coverage
- Check against the `testing` convention (resolved via the lookup in `plugin-main.md`):
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

Append a report to `paths.impl_report` (= `paths.temp`) using `paths.block_impl_report` (`## Implementation Review`) as the block header. Follow the Block Writing Pattern from `plugin-main.md`.

If all criteria pass:

```markdown
## Implementation Review

STATUS: PASS
```

If any criterion has concerns:

```markdown
## Implementation Review

STATUS: CONCERN

### Concerns

#### <Criterion name>
- <file path>:<line> — <specific concern and what needs to change>

#### <Criterion name>
- <specific concern>
```

Do **not** ask the user any questions and do **not** modify any files — the orchestrator handles that.
