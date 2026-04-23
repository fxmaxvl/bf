---
name: verify
description: Run quality gates (tests + lint) for the feature. Detects project type, consults conventions, runs tests (monorepo-aware), and runs linters with auto-fix.
disable-model-invocation: true
model: sonnet
allowed-tools: Read, Grep, Glob, Bash
---

Run quality gates for this project.

## Step 1 — Load state and detect stack

Run the two helper scripts:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/full/scripts/state-ops.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/full/scripts/detect-stack.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/full/scripts/changed-packages.sh"
```

`state-ops.sh` gives you `slug`, `mode`, and all artifact paths.
`detect-stack.sh` gives you `type`, `test_commands`, `lint_command`, `lint_fix_command`, `monorepo`, `workspaces`, and `scope_template`.
`changed-packages.sh` gives you `changed_files` and `affected_packages`.

**If the project is TypeScript/JavaScript**, also read `${CLAUDE_PLUGIN_ROOT}/conventions/typescript.md` for any project-specific lint and test overrides.
**For all projects**, read `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md` for test requirements.

If monorepo is true, scope test and lint commands to the affected package using `scope_template` — do not run commands for the whole monorepo.

## Step 2 — Run tests

Use `test_commands` from `detect-stack.sh`. If monorepo, apply `scope_template` using the first entry in `affected_packages`. Run each command in `test_commands`.

Run the full test suite (all tests in scope, not just changed files — the goal is to ensure nothing is broken).

**If tests fail:**
1. Identify which tests failed and which files they test
2. Cross-reference with `changed_files` from `changed-packages.sh`
3. **If the failing test covers code that was changed by this feature:**
   - Fix the code or test causing the failure
   - Re-run the test suite
   - Repeat until green
4. **If the failing test is in a file NOT in `changed_files`:**
   - Treat this as a **pre-existing failure** — it existed before this feature branch
   - **Do NOT attempt to fix it**, even if the fix looks obvious
   - Report to the user: "Pre-existing test failure detected: `[test name / file]`. This file was not changed by this feature — the failure likely predates this branch. Skipping and continuing."
   - Proceed to lint without waiting for a response

All tests in scope must be green (or explicitly skipped by user) before proceeding.

## Step 3 — Run linters

Use `lint_command` and `lint_fix_command` from `detect-stack.sh`. If monorepo, apply `scope_template`.

Run the linter. **If issues are found:**
1. If `lint_fix_command` is non-null → run it **scoped to `changed_files` only** (the files changed by this feature, from `changed-packages.sh`) — do not auto-fix files outside that set. Then re-run the linter to verify.
2. If still issues after auto-fix, or no auto-fix available → fix the issues manually (do NOT suppress or disable linter rules)
3. Re-run the linter to confirm green
4. **If any files were modified during lint fixing:** commit them immediately — read `conventions/git.md` for format, use `style:` prefix (e.g., `style: apply prettier auto-fixes`). Do not leave lint fixes as unstaged changes.

All lint checks must pass before completing.

## Output

When both tests and lint are green, print a brief summary:
- Test suite: N passed, 0 failed
- Lint: clean

Do **not** modify any plan, spec, or state files — the orchestrator manages state.
Do **not** ask the user any questions during execution.
