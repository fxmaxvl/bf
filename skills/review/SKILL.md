---
name: review
description: Review code against feature conventions and the complexity gate. Pass a free-form description of what to review (e.g. a PR number, file paths, a commit range, or a natural-language description) or omit to review the current branch.
model: opus
disable-model-invocation: false
argument-hint: "[--dry-run] [free-form: 'PR 42', 'https://github.com/org/repo/pull/42', 'src/auth/', 'last 3 commits', or empty for current branch]"
allowed-tools: Read, Write, Grep, Glob, Agent, Bash(git *), Bash(gh *), Bash(mktemp *), Bash(mkdir *), Bash(ln *), Bash(date *), Bash(rm *), Bash(sed *), Bash(basename *), Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill, including the **one-question-per-turn** rule that applies at every interactive point in this skill.

## On Invocation

### Verify git repo

Run: `git rev-parse --show-toplevel`

If this fails, print: "Not a git repository. Exiting." and stop.

Set `project_root` to the output.

### Detect --dry-run

Parse `$ARGUMENTS` for a `--dry-run` token (match it as a standalone word, not as a substring). If present:

- Set `dry_run=true`.
- Strip the token from `$ARGUMENTS` — the remaining text is the normal scope description (e.g. `PR 42`, `src/auth/`, empty for current branch).

Otherwise set `dry_run=false`.

### Resolve focus

A focus narrows the review to one or more angles. It is exclusive: only the checks the chosen lenses need run, and everything else is skipped rather than de-prioritised. No focus means the full review.

**Lens table.** This is the single source of truth for lenses. Every later section refers to it rather than restating it. Categories are the numbered sections of the Code Review Convention.

| Lens | Review-agent categories | Gates |
|---|---|---|
| `quality` | Code Structure & Fit (§4), Readability & Quality (§5) | complexity, consistency |
| `complexity` | — | complexity |
| `consistency` | — | consistency |
| `security` | Security (§3) | — |
| `tests` | Testing (§2) | — |
| `conventions` | Dev Conventions (§1) | — |

**Explicit flag.** Parse `$ARGUMENTS` for a `--focus` token (a standalone word, as with `--dry-run`). Its value is the next token, split on commas, e.g. `--focus quality,security`. Strip both tokens from `$ARGUMENTS`. It composes with `--dry-run` in either order. When `--focus` is present it wins: the remaining text is scope only and is never read for focus.

**Free text.** Without `--focus`, read the remaining text for an angle. When it clearly asks *how* to look at the code rather than *what* to review, map it to lenses and treat the rest as scope. For example, "can we make this look nicer" → `quality`, "any security holes?" → `security`, and "PR 42, are the tests good enough" → `tests` with scope `PR 42`. Text that only names a scope, or empty text, means a full review.

**Unknown lens.** If a `--focus` value is not in the lens table, ask one question that lists the valid lenses and asks which was meant, then re-parse the answer.

**Ambiguous split.** If it is unclear whether part of the text is scope or focus (e.g. "review src/auth for security issues"), ask one question. Offer "Full review of `<scope>`" (Recommended) first and "Only the `<lens>` lens on `<scope>`" second.

**Unattended runs.** When nobody can answer, e.g. inline under `bf:autopilot`, ask neither question. An oracle could pick the narrow reading, and an unattended run must not silently skip checks. Take the widest reading, a full review, and record the assumption in `focus_label`.

**Focus variables.** Set these once. Later phases use them and never re-read `$ARGUMENTS`:

- `focus_lenses`: the resolved lenses in lens-table order; empty for a full review.
- `focus_categories`: the union of their review-agent categories; for a full review, all five.
- `run_review`: true when `focus_categories` is non-empty.
- `run_complexity` / `run_consistency`: true when any chosen lens lists that gate; both true for a full review.
- `focus_label`: `full` for a full review, otherwise the comma-joined `focus_lenses`. When an unattended run fell back, use `full (assumed — <short reason>)`.
- `status_suffix`: empty for a full review, otherwise ` (focus: <focus_lenses>)`. Every STATUS line this skill writes for the review report ends with it, e.g. `STATUS: PASS (focus: quality)`. A focused pass is never a full pre-PR check.

### Compute report paths

Resolve the artifact root with the 2-step lookup from `plugin-main.md` — the project's own
`.bf/` first, `~/.bf/` only when there is no repo:

```bash
timestamp=$(date -u +%Y%m%dT%H%M%S)
project_root=$(git rev-parse --show-toplevel 2>/dev/null)
reports_dir="${project_root:+$project_root/.bf}"
reports_dir="${reports_dir:-$HOME/.bf}/reviews"
report_path="$reports_dir/${timestamp}-review.md"
```

Create the reports directory: `mkdir -p "$reports_dir"`

### Print banner

```
── bf:review ───────────────────────────────────────────
```

Print as plain text, not in a code block. If `dry_run=true`, append ` (dry-run)` to the banner line. On the next line print `Focus: <focus_label>`.

### Dry-run preview (if dry_run=true)

When `dry_run=true`, skip every Agent spawn and exit before Phase 1 work begins. Print a structured preview so the user can see exactly what would run, then stop. No report is written, no `build-state.json` is created, no symlink is updated.

Steps:

1. Resolve conventions exactly as Phase 1 does — perform the 3-step lookup for `code-review`, `dev`, `testing`, `architecture` — but do **not** read the file bodies. Capture only the resolved absolute paths.
2. Print this block (plain text, not in a code fence):

   ```
   bf:review — dry-run
   Scope: <scope description: "current branch diff vs origin/HEAD" if the scope text is empty, else the scope text left after flags and focus are stripped>
   Focus: <focus_label>
   Report would be written to: <report_path>
   Resolved conventions:
     - code-review: <resolved path or "MISSING">
     - dev:         <resolved path or "MISSING">
     - testing:     <resolved path or "MISSING">
     - architecture: <resolved path or "MISSING">
   Agents that would be spawned (skipped in dry-run):
     - review Agent        (model: opus) — Phase 1 parallel batch
     - complexity-gate Agent (model: opus) — Phase 1 parallel batch
     - consistency-gate Agent (model: opus) — Phase 1 parallel batch
   All <N> dispatched in a single message; results aggregated in Phase 2.
   Interactive phases that would follow (skipped in dry-run):
     - Phase 3 fix selection
     - Phase 4 fix apply + re-review
   ```

   List only the agents whose `run_review` / `run_complexity` / `run_consistency` is true. Do not name the others, not even as skipped. When only one agent would run, replace the "All <N> dispatched" line with "Dispatched alone; results aggregated in Phase 2."

3. Exit. Do not proceed to Phase 1.

## Phase 1 — Review

### Resolve conventions

Resolve each convention using the 3-step lookup from `plugin-main.md`:

1. `<project_root>/.bf/conventions/<name>.md`
2. `~/.bf/conventions/<name>.md`
3. `${CLAUDE_PLUGIN_ROOT}/conventions/<name>.md`

Resolve: `code-review`, `dev`, `testing`, `architecture`.

Record the four resolved absolute paths. Do **not** read the files — the prompts below pass the paths and each agent reads what it needs itself.

### Resolve scope and changed_files

Before spawning any Agent, compute the review scope from `$ARGUMENTS` (after `--dry-run` has been stripped):

1. **Detect PR URL**: if `$ARGUMENTS` contains a GitHub PR URL (e.g. `https://github.com/org/repo/pull/123`), extract `pr_number`:
   ```bash
   pr_number=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')
   ```
   Then treat the input as if the user had passed the bare `pr_number`.

2. **Resolve the scope in one call.** `scope.sh` already implements the branch, range
   and paths modes, and `--with-diff` returns the diff as a **path** rather than a
   value — so the diff never has to pass through this conversation. Do not hand-derive
   a diff or a file list.

   **Normalize the target first.** `scope.sh` dispatches on the literal `branch`, on a
   rev or range `git rev-parse --verify` accepts, or on a pathspec — and anything else
   falls through to a pathspec, which matches nothing and reviews nothing. So translate
   a free-form request before passing it:

   | `$ARGUMENTS` | target to pass |
   |---|---|
   | empty, or a bare "current branch" | `""` |
   | a natural-language range, e.g. "last 3 commits" | the equivalent rev range, e.g. `HEAD~3...HEAD` |
   | a free-form PR reference, e.g. "PR 42" | none — use the PR case below |
   | a rev, a range, or file paths | unchanged |

   - **Anything that is not a PR** — pass the normalized target through. An empty target
     resolves to uncommitted changes, falling back to branch-vs-base when the tree is
     clean:
     ```bash
     scope=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/coherence/scripts/scope.sh" --with-diff "$target")
     ```
     Read `mode`, `files`, `file_count` and `diff_file` from the returned JSON. Set
     `changed_files` from `files`, `diff_file` from `diff_file`, `pr_head_branch=""`,
     and `scope_description` from the original request (e.g. "current branch diff vs
     origin/HEAD" for `branch`, the literal paths for `paths`).

   - **PR number** (bare integer or extracted `pr_number`): `scope.sh` has no PR mode,
     so resolve this one through `gh` and write the diff to a file rather than a
     variable:
     ```bash
     diff_file=$(mktemp)
     gh pr diff <pr_number> > "$diff_file"
     changed_files=$(sed -n 's#^diff --git a/.* b/##p' "$diff_file")
     pr_head_branch=$(gh pr view <pr_number> --json headRefName -q .headRefName)
     scope_description="PR <pr_number>"
     ```

   For file-path inputs where the diff may be empty (e.g. unmodified files explicitly
   listed), fall back to the literal paths from `$ARGUMENTS` for `changed_files`.

3. **Early exit if nothing to review**: if `changed_files` is empty:
   ```
   STATUS: NOTHING_TO_REVIEW — no changed files found for scope: <scope_description>
   ```
   Print this and stop. Do not spawn any Agent.

### Write temporary build-state.json

Skip this step, and the matching cleanup, when both `run_complexity` and `run_consistency` are false: no gate will run, so an in-progress feature's state is left untouched.

`state-ops.sh` requires a `build-state.json` file. Create it now so the gate sub-skills can run later in the parallel batch. `--init` builds the whole file and returns the computed artifact paths, so do not hand-write the JSON or re-derive the path formula.

```bash
temp_state="$project_root/.bf/sessions/build-state.json"
temp_state_backup="$temp_state.bfreview-backup"
```

**If `$temp_state` already exists**, move it aside first — `--init` refuses to overwrite an existing state file:

```bash
[ -f "$temp_state" ] && mv "$temp_state" "$temp_state_backup" && \
  echo "Warning: .bf/sessions/build-state.json already exists — a feature workflow may be in progress. Moving it aside; it will be restored after the complexity scan."
```

Then initialize the state and read the paths it returns:

```bash
paths_json=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" --init \
  --slug "review-${timestamp}" --idea "bf:review complexity scan" --mode review)
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=verify phase_status=in_progress
complexity_report_path=$(echo "$paths_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["paths"]["complexity_report"])')
```

### Pre-review: check for existing integration/E2E tests

Skip this step unless Testing is in `focus_categories`. The test-coverage context only informs Testing concerns.

Before spawning the review agent, list the project's tracked integration and E2E test files.
`git ls-files` respects `.gitignore`, so it never descends `dist/`, `build/`, `.venv/` or
`target/` the way a bare `find` does:

```bash
int_tests=$(git -C "$project_root" ls-files \
  | grep -E "\.(test|spec|e2e)\." | grep -iE "(integration|e2e|end.to.end)" | head -20)
has_integration_tests=$([ -n "$int_tests" ] && echo yes || echo no)
has_e2e_tests=$(echo "$int_tests" | grep -qiE "(e2e|end.to.end)" && echo yes || echo no)
```

Read `has_integration_tests` and `has_e2e_tests` from that output — do not re-derive them by
eyeballing the paths.

### Spawn the enabled Agents in parallel (model: opus)

Spawn only the Agents the focus enables: the review Agent when `run_review`, the complexity-gate when `run_complexity`, the consistency-gate when `run_consistency`. A full review enables all three.

Print (plain text) a line naming what runs, e.g. `→ Reviewing + running complexity + consistency gates with opus… (this usually takes a few minutes)` for a full review, or `→ Reviewing (focus: security) with opus…`.

Build the prompts for the enabled Agents:

**Prompt A — review Agent:**

```
You are a code reviewer.

## Conventions

Read each of these files and apply it strictly:

- Dev: <resolved absolute path to dev.md>
- Testing: <resolved absolute path to testing.md>
- Architecture: <resolved absolute path to architecture.md>
- Code review: <resolved absolute path to code-review.md>

## Scope

The review scope has already been resolved by the orchestrating skill.

changed_files:
<one path per line from changed_files>

scope_description: <scope_description>

diff_file: <diff_file>

pr_head_branch: <pr_head_branch if non-empty, else omit>

## Test Coverage Context

<include this block only when Testing is in focus_categories>

Integration tests found in package: <has_integration_tests>
E2E tests found in package: <has_e2e_tests>

Sample paths (up to 20):
<$int_tests if non-empty, otherwise: "(none found)">

When flagging missing integration or E2E tests:
- If `has_integration_tests` is "yes", do NOT flag missing integration tests unless the changed functionality has no integration test coverage at all.
- If `has_e2e_tests` is "yes", do NOT flag missing E2E tests unless the changed functionality has no E2E test coverage at all.
- If both are "no", flag their absence as a `[must-fix]` concern under Testing.

## Instructions

1. The changed files are listed in the `## Scope` block above and the diff is on disk at `diff_file` — read it with the Read tool. Do NOT re-run git or gh to re-derive the scope.
2. Read the full current content of each file listed in `changed_files` using the Read tool before forming conclusions.
3. Apply the checks in these sections of the Code Review Convention: <the § numbers and names in focus_categories>. <When focused, add: "Do not check or report on any other category.">
4. Produce the report in this exact format — including the Review Metadata block at the end:

# Code Review Report
- Scope: <human-readable description of what was reviewed>
- Timestamp: <ISO 8601>
- Files reviewed: <count>
- Focus: <focus_label>

STATUS: PASS<status_suffix> | CONCERN<status_suffix>

## Summary
<2–4 sentence summary of what changed and overall quality>

## Concerns

### Dev Conventions
- **C1** [must-fix] `file:line` — <problem> — Suggested: <fix>

### Testing
- **C2** [must-fix] `file:line` — <problem> — Suggested: <fix>

### Security
- **C3** [must-fix] `file:line` — <problem> — Suggested: <fix>

### Code Structure & Fit
- **C4** [should-consider] `file:line` — <problem> — Suggested: <fix>

### Readability & Quality
- **C5** [should-consider] `file:line` — <problem> — Suggested: <fix>

<List only the section headers for the categories in focus_categories.>

Numbering: C1, C2, C3, ... sequentially across all sections.
Label each concern [must-fix] or [should-consider].
Omit sections that have no concerns.
If STATUS is PASS, omit the Concerns block entirely.

## Review Metadata
changed_files:
<one path per line — every file reviewed>
pr_head_branch: <branch name if this was a PR review, else omit this line>

Return only the report — no preamble or commentary.
```

**Prompt B — complexity-gate Agent** (prepend override block, then SKILL.md contents):

```
## OVERRIDE — changed_files

Do NOT run `changed-packages.sh`. Treat the following paths as `changed_files` instead:

<one path per line from changed_files>

Proceed with scan mode using these paths.

Read <resolved absolute path to skills/feature/complexity-gate/SKILL.md> and follow it.
```

**Prompt C — consistency-gate Agent** (same pattern):

```
## OVERRIDE — changed_files

Do NOT run `changed-packages.sh`. Treat the following paths as `changed_files` instead:

<one path per line from changed_files>

Proceed with scan mode using these paths.

Read <resolved absolute path to skills/feature/consistency-gate/SKILL.md> and follow it.
```

Dispatch the enabled Agents in a **single message** (all model: opus), so they run in parallel. Wait for all of them to return.

### Clean up temp state

When the temp state was written, after every spawned Agent returns (whether they succeed or fail):

```bash
rm -f "$temp_state"
[ -f "$temp_state_backup" ] && mv "$temp_state_backup" "$temp_state"
```

**This cleanup must happen on every exit path — including when the review Agent fails — do not skip it.**

## Phase 2 — Aggregate Results

### Save review report and extract metadata

**When `run_review` is false** (the focus has no review-agent categories), no review Agent ran. This is not a failure, so do not set `review_failed`. Write the report header yourself to `$report_path`, keep the pre-computed `changed_files` and `pr_head_branch`, and go on to the merge:

```
# Code Review Report
- Scope: <scope_description>
- Timestamp: <ISO 8601>
- Files reviewed: <count of changed_files>
- Focus: <focus_label>

STATUS: PASS<status_suffix>

## Summary
Focused review: only the <complexity and/or consistency> gate ran. Its results are below.
```

If the review Agent returned a valid report (output starts with `# Code Review Report`):

Write the Agent's output to `$report_path`.

Update the symlink: `ln -sf "$report_path" "$reports_dir/latest.md"`

Extract `changed_files` (authoritative list): the pre-computed `changed_files` from Phase 1 is the source of truth and was fed to all three Agents. Optionally cross-check against the `## Review Metadata` block in the report — if the Agent lists additional files it read, add them. If the Agent lists fewer files than pre-computed, keep the pre-computed list.

Extract `pr_head_branch`: read the `pr_head_branch:` line from `## Review Metadata`. If absent, use the pre-computed `pr_head_branch` from Phase 1.

If the review Agent failed or returned output that does not start with `# Code Review Report`:
- Print: `⚠ Review Agent failed — complexity and consistency results are still available.`
- Set `review_failed=true`.
- Do not write `$report_path`. Proceed to merge complexity and consistency findings only.

### Merge complexity and consistency findings into report

**When `review_failed=true`**: create a minimal report stub at `$report_path` before appending:

```
# Code Review Report (partial — review Agent failed)
- Scope: <scope_description>
- Timestamp: <ISO 8601>
- Files reviewed: <count of changed_files>
- Focus: <focus_label>

STATUS: CONCERN<status_suffix>

## Summary
Review Agent did not complete. Complexity and consistency results are below.
```

A gate the focus did not enable was never spawned. Skip its merge step and omit its section entirely; never write `UNKNOWN` for it.

**Complexity** (when `run_complexity`)**:** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "$complexity_report_path" --block "## Complexity Report"` to extract the STATUS. If the file does not exist or the Agent failed, continue with: `## Complexity\nSTATUS: UNKNOWN (complexity gate failed — see conversation)`.

Renumber all complexity findings as X1, X2, ... sequentially.

Map severity:
- BLOCK finding → `[must-fix]`
- ADVISORY finding → `[should-consider]`

Append to the report at `$report_path`:

```
## Complexity
STATUS: <PASS | ADVISORY | BLOCK>

### <Root Cause / Red Flag>
- **X1** [must-fix | should-consider] `file:line` — <observation> — Suggested: <fix>
```

Omit the section body if STATUS is PASS.

**Consistency** (when `run_consistency`)**:** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "$complexity_report_path" --block "## Consistency Report"` to extract the STATUS. If the file does not exist or the Agent failed, continue with: `## Consistency\nSTATUS: UNKNOWN (consistency gate failed — see conversation)`.

Renumber all consistency findings as Y1, Y2, ... sequentially.

Map severity identically (BLOCK → `[must-fix]`, ADVISORY → `[should-consider]`).

Append to the report at `$report_path`:

```
## Consistency
STATUS: <PASS | ADVISORY | BLOCK>

### <Lens>
- **Y1** [must-fix | should-consider] `file:line or spec section` — <observation> — Suggested: <fix>
```

Omit the section body if STATUS is PASS.

### Escalate overall STATUS

If any C*, X*, or Y* concern exists, or if `review_failed=true`, set overall STATUS to CONCERN.

Rewrite `$report_path` with the merged content (replace the STATUS line at the top, keeping `<status_suffix>`).

Update the symlink: `ln -sf "$report_path" "$reports_dir/latest.md"`

### Show summary in conversation

Print:

```
STATUS: <PASS | CONCERN><status_suffix>
Focus: <focus_label>
Concerns: <N> code (<M> must-fix), <X> complexity, <Y> consistency
Report: <report_path>
```

On the `Concerns:` line, list counts only for the parts that ran.

If `review_failed=true`, also print: `⚠ Review Agent failed — code concerns (C*) are not available. Fix selection in Phase 3 is limited to X* and Y* findings.`

## Phase 3 — Fix Selection

**One-question-per-turn rule applies in this phase.** Ask step 1 and wait for the answer before asking step 2. Never batch both into one message.

### If STATUS is PASS

Print: "No concerns found. Report saved at `<report_path>`." and exit.

### If STATUS is CONCERN

**Step 1 — Selection question**

Print a one-line summary of each concern:

```
C1 [must-fix]        src/foo.ts:42 — <problem description>
C2 [should-consider] src/bar.ts:8 — <problem description>
X1 [must-fix]        src/baz.ts:15 — <complexity finding>
Y1 [should-consider] src/qux.ts:3 — <consistency finding>
```

Then ask (one question only):

> Which concerns would you like to fix? Reply with IDs (e.g. `C1 X1 Y2`), `all`, `must-fix`, or `none`.

Wait for the user's reply before proceeding.

**Parse the answer:**

- `none` or empty → select nothing.
- `all` → select all C*, X* and Y* concerns.
- `must-fix` → select all concerns labelled `[must-fix]`.
- Space-separated IDs → validate each ID exists in the report.
  - If any ID is unknown, ask once: "Unknown ID(s): <list>. Please re-enter valid IDs from the list above." Re-parse the new answer; if still invalid, treat as `none`.

Set `selected_concerns` to the validated list.

**Mark what was not selected.** Every concern left out — including all of them when the answer was `none`, empty, or never given — gets `[deferred]` appended to its label line in the saved report, so a concern that was seen and passed over is distinguishable from one nobody ruled on:

```
- **C4** [should-consider] [deferred] `file:line` — <problem> — Suggested: <fix>
```

If nothing was selected, print "No fixes requested. <N> concern(s) marked `[deferred]` in the report at `<report_path>`." and exit. Never exit leaving concerns unlabelled.

**Step 2 — Confirmation question**

Print: "Will fix: <selected IDs>. Proceed? (yes/no)"

Wait for reply.

- `yes` (or `y`) → proceed to Phase 4.
- anything else → return to Step 1.

## Phase 4 — Fix

### PR review: check out the PR branch

If `pr_head_branch` is non-empty:

```bash
git fetch origin "$pr_head_branch"
git checkout "$pr_head_branch"
```

If checkout fails, tell the user: "Could not check out PR branch `<pr_head_branch>`. Fixes cannot be applied automatically — address the concerns manually." and exit Phase 4.

### Spawn fix Agent (model: sonnet)

Print (plain text): `→ Applying <N> fix(es) with sonnet…`

Collect the selected concerns from the report: extract the full description blocks for each selected ID.

Pass the following prompt to an Agent with model: sonnet:

```
You are applying code fixes identified by a code review.

## Dev Convention

Read <resolved absolute path to dev.md> and apply it.

## Selected Concerns
<concern block for each selected ID, preserving full text>

## Changed Files
<one path per line from changed_files>

## Instructions

- You are running in the main working tree rooted at `<project_root>`. Do NOT create or use a git worktree. Do NOT checkout a different directory. Edit source files directly using their absolute paths under `<project_root>`.
- Apply each fix in place. Every write must target a file listed in the `## Changed Files` block above.
- Do not commit or push anything.
- If a fix cannot be applied cleanly (e.g. the code has moved), add a TODO comment:
  `// TODO(bf:review): <concern ID> — <brief description of what needs manual fixing>`
- Return a brief summary: which concerns were applied, which were deferred with a TODO.
```

### Post-fix test check

After the fix Agent returns, check whether the project has a test suite:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/detect-stack.sh"
```

This gives you `test_commands`. If `test_commands` is non-empty:

1. Run each test command. Capture stdout+stderr combined. Note the exit code.
2. If all commands exit 0: proceed to the re-review cycle below.
3. If any command exits non-zero:
   a. Print (plain text): `⚠ Tests failed after fix — running correction loop…`
   b. Spawn a correction Agent (model: sonnet) with this prompt:
      ```
      The fix you applied caused test failures. Fix only the failing test assertions.

      ## Test Output
      <captured test output>

      ## Changed Files
      <one path per line from changed_files>

      ## Instructions
      - Read the failing test files.
      - Update only stale test assertions caused by the structural fix — do not change test intent or coverage.
      - Do not commit or push anything.
      - Return a brief summary of what you changed.
      ```
   c. After the correction Agent returns, run the test commands once more.
   d. If still failing: print `⚠ Tests still failing after correction. Proceeding to re-review; manual test fixes may be needed.` — then proceed anyway. Do not loop more than once.

If `test_commands` is empty: skip this step and proceed directly to the re-review cycle.

### Re-review cycle

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

## Files to Re-review
<one path per line from changed_files>

## Instructions

1. Read the full current content of each file using the Read tool.
2. Apply every check in the Code Review Convention.
3. Produce the same report format as before (# Code Review Report … ## Review Metadata).
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

## Edge Cases & Errors

### Startup

| Condition | Handling |
|-----------|----------|
| Not a git repository | Print "Not a git repository. Exiting." and stop. |
| `<project_root>/.bf` not writable | Fall back to `~/.bf/reviews/` for `reports_dir`. Warn the user. |
| Convention file missing (all 3 lookup paths absent) | Print "Convention file not found: <last-looked-up path>. This may be a plugin install issue." and stop. |
| `--focus` names a lens not in the lens table | Ask which valid lens was meant. When unattended, run the full review with `focus_label` = `full (assumed — unknown lens <name>)`. |
| Unclear whether text is scope or focus | Ask, with the full review recommended. When unattended, run the full review with `focus_label` = `full (assumed — <reason>)`. |

### Phase 1 — Parallel batch

| Condition | Handling |
|-----------|----------|
| Nothing to review (empty diff, no files match) | Pre-check exits with `STATUS: NOTHING_TO_REVIEW` before any Agent is spawned. |
| `gh` error (not installed, not authenticated, PR not found) | Scope resolution fails — print the error and exit before spawning any Agent. |
| Review Agent fails or returns invalid output | Surfaces warning; write partial report stub; proceed with X*/Y* aggregation. |
| Complexity Agent fails or errors | Append `STATUS: UNKNOWN` block. Do not block the review. |
| Consistency Agent fails or errors | Append `STATUS: UNKNOWN` block. Do not block the review. |
| Focus has no review-agent categories | No review Agent is spawned. Write the report header directly; this is not `review_failed`. |
| Focus excludes a gate | That gate is not spawned. Omit its section; do not write `UNKNOWN`. |
| `build-state.json` already exists | Move it aside, warn the user, restore after scan. |

### Fix phase

| Condition | Handling |
|-----------|----------|
| Fix Agent fails | Inform the user, skip re-review, print original report path only. |
| User never answers the fix-selection question | Mark every concern `[deferred]` in the saved report before exiting, so the next reader can tell the concerns were surfaced and left unruled rather than never raised. |
| Re-review finds new concerns not in the original | Include in "remaining" count, label `[new]`. |

### Re-invocation

This skill is stateless — each invocation produces a fresh timestamped report. `latest.md` always points to the most recent report. Previous reports are preserved.
