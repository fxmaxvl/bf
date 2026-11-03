# Phase 4 — Fix

### PR review: check out the PR branch

If `pr_head_branch` is non-empty, check out the PR with `gh pr checkout`, which finds the right remote for a fork PR itself:

```bash
cd "<project_root>" && gh pr checkout <pr_number> -R "<pr_repo>" && git rev-parse HEAD
```

If it fails with `Not possible to fast-forward`, gh has already switched to the local branch, which has diverged from the PR: tell the user "Local branch `<pr_head_branch>` has diverged from the PR and is now checked out. Reconcile it, then re-run the fixes." On any other failure, tell the user: "Could not check out PR branch `<pr_head_branch>`. bf:review cannot apply the fixes automatically. Address the concerns manually." If the printed SHA is not `pr_head_sha`, tell the user "PR <pr_number> has new commits since the review. Re-run /bf:review on it, then apply the fixes." Exit Phase 4 in each of these cases.

Then run the Phase 1 `resolve-conventions.sh` call again and use the new paths in every prompt from here on. A project-tier convention can exist on one branch and not on the other.

### Spawn fix Agent (model: sonnet)

Print (plain text): `→ Applying <N> fix(es) with sonnet…`

Collect the selected concerns from the report: extract the full description blocks for each selected ID.

Pass the following prompt to an Agent with model: sonnet:

```
You are applying code fixes identified by a code review.

## Dev Convention

Read <resolved absolute path to dev.md> and apply it.

## Prose

Apply the rules in <resolved absolute path to prose.md> to code comments and to all prose you return.

## Selected Concerns
<concern block for each selected ID, preserving full text>

## Changed Files
<one path per line from changed_files>

## Instructions

- You are running in the main working tree rooted at `<project_root>`. Do NOT create or use a git worktree. Do NOT checkout a different directory. Edit source files directly using their absolute paths under `<project_root>`.
- Apply each fix in place. Every write must target a file listed in the `## Changed Files` block above.
- Do not commit or push anything.
- If a fix cannot be applied cleanly (e.g. the code has moved), add a TODO comment:
  `// TODO(bf:review): <concern ID>: <brief description of what needs manual fixing>`
- Return a brief summary: which concerns were applied, which were deferred with a TODO.
```

### Post-fix test check

After the fix Agent returns, check whether the project has a test suite:

```bash
cd "<project_root>" && bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/detect-stack.sh"
```

This gives you `test_commands`. If `test_commands` is non-empty:

1. Run each test command from `<project_root>`. Capture stdout+stderr combined. Note the exit code.
2. If all commands exit 0: proceed to the re-review cycle below.
3. If any command exits non-zero:
   a. Print (plain text): `⚠ Tests failed after fix. Starting the correction loop…`
   b. Spawn a correction Agent (model: sonnet) with this prompt:
      ```
      The fix you applied caused test failures. Fix only the failing test assertions.

      ## Prose

      Apply the rules in <resolved absolute path to prose.md> to code comments and to all prose you return.

      ## Test Output
      <captured test output>

      ## Changed Files
      Relative to <project_root>:
      <one path per line from changed_files>

      ## Instructions
      - Read the failing test files.
      - Update only stale test assertions caused by the structural fix — do not change test intent or coverage.
      - Do not commit or push anything.
      - Return a brief summary of what you changed.
      ```
   c. After the correction Agent returns, run the test commands once more.
   d. If still failing: print `⚠ Tests still fail after correction. Starting the re-review. The tests may need manual fixes.` — then proceed anyway. Do not loop more than once.

If `test_commands` is empty: skip this step and proceed directly to the re-review cycle.

### Re-review cycle

**When `run_review` is false** (a gates-only focus), skip the re-review. It only ever spawns a review Agent, and gates are not re-run after fixes in a full review either. Tell the user instead:

```
Original report: <report_path>
Applied: <N> fix(es)
Re-run `/bf:review --focus <focus_lenses>` to re-check the gates.
```

Otherwise the re-review keeps the original focus, so a focused first pass never widens into a full review. The one exception is the check on lines the fix itself touched (step 3 of the prompt below), because a fix can break a rule outside the focus it was made for.

Print (plain text): `→ Re-reviewing post-fix (cycle <N>) with opus…`

After the fix Agent returns, spawn a new review Agent (same conventions, model: opus) with the following prompt:

```
You are a code reviewer performing a re-review after fixes were applied.

## Conventions

Read each of these files and apply it strictly:

- Dev: <resolved absolute path to dev.md>
- Testing: <resolved absolute path to testing.md>
- Architecture: <resolved absolute path to architecture.md>
- Code review: <resolved absolute path to code-review.md>
- Prose (for all prose you return): <resolved absolute path to prose.md>

Host repository rules (apply as the Code Review Convention describes): <one path per line from host_rules, or "none">

## Files to Re-review
Relative to <project_root>:
<one path per line from changed_files>

## What the Fix Changed
<the selected concern blocks passed to the fix Agent, then the fix Agent's returned summary>

## Instructions

1. Read the full current content of each file using the Read tool.
2. Apply the checks in these sections of the Code Review Convention: <the § numbers and names in focus_categories>. <When focused, add: "Do not check or report on any other category, except as step 3 requires.">
3. Whatever the focus, check every line the fix touched (per "What the Fix Changed") against these rules, and report anything the fix introduced labelled `[new]`:
   - the **Comments** rule in <absolute path to ${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md>;
   - the style rule in the Dev convention — the change matches the surrounding code's style and formatting;
   - the host repository rules listed above.
4. Produce the same report format as before (# Code Review Report … ## Review Metadata), with `- Focus: <focus_label>` in the header, `<status_suffix>` on the STATUS line, and section headers only for the categories above, plus any category a `[new]` finding from step 3 falls under.
   For changed_files in Review Metadata, repeat the same file list.
```

Cap at 2 re-review cycles. Do not run a third fix→review round.

Set `after_fix_report_path` to `${report_path%.md}-after-fix.md` (or `-after-fix-2.md` for cycle 2).

Save the new report to `after_fix_report_path`. Update `latest.md` symlink. Do not overwrite the original `$report_path`.

### Tell the user

```
Original report:  <report_path>
After-fix report: <after_fix_report_path>
Resolved:  <N> concerns addressed
Remaining: <M> concerns still present
```

List remaining concerns by ID and label if any exist.
