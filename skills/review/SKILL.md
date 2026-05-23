---
name: review
description: Review code against feature conventions and the complexity gate. Pass a free-form description of what to review (e.g. a PR number, file paths, a commit range, or a natural-language description) or omit to review the current branch.
model: opus
disable-model-invocation: false
argument-hint: "[--dry-run] [free-form: 'PR 42', 'https://github.com/org/repo/pull/42', 'src/auth/', 'last 3 commits', or empty for current branch]"
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), Bash(mkdir *), Bash(ln *), Bash(date *), Bash(rm *), Bash(sed *), Bash(basename *)
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

### Compute project_id and report paths

```bash
PROJECT_ID=$(git config --get remote.origin.url 2>/dev/null \
  | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$project_root")
timestamp=$(date -u +%Y%m%dT%H%M%S)
reports_dir="$HOME/.bf/$PROJECT_ID/reviews"
report_path="$reports_dir/${timestamp}-review.md"
```

Create the reports directory: `mkdir -p "$reports_dir"`

### Print banner

```
── bf:review ───────────────────────────────────────────
```

Print as plain text, not in a code block. If `dry_run=true`, append ` (dry-run)` to the banner line.

### Dry-run preview (if dry_run=true)

When `dry_run=true`, skip every Agent spawn and exit before Phase 1 work begins. Print a structured preview so the user can see exactly what would run, then stop. No report is written, no `build-state.json` is created, no symlink is updated.

Steps:

1. Resolve conventions exactly as Phase 1 does — perform the 3-step lookup for `code-review`, `dev`, `testing`, `architecture` — but do **not** read the file bodies. Capture only the resolved absolute paths.
2. Print this block (plain text, not in a code fence):

   ```
   bf:review — dry-run
   Scope: <scope description: "current branch diff vs origin/HEAD" if $ARGUMENTS is empty, else the literal $ARGUMENTS>
   Report would be written to: <report_path>
   Resolved conventions:
     - code-review: <resolved path or "MISSING">
     - dev:         <resolved path or "MISSING">
     - testing:     <resolved path or "MISSING">
     - architecture: <resolved path or "MISSING">
   Agents that would be spawned (skipped in dry-run):
     - Phase 1 review Agent (model: opus)
     - Phase 2 complexity-gate Agent (model: opus)
     - Phase 2 consistency-gate Agent (model: opus)
   Interactive phases that would follow (skipped in dry-run):
     - Phase 3 fix selection
     - Phase 4 fix apply + re-review
   ```

3. Exit. Do not proceed to Phase 1.

## Phase 1 — Review

### Resolve conventions

Resolve each convention using the 3-step lookup from `plugin-main.md`:

1. `<project_root>/.bf/conventions/<name>.md`
2. `~/.bf/conventions/<name>.md`
3. `${CLAUDE_PLUGIN_ROOT}/conventions/<name>.md`

Resolve: `code-review`, `dev`, `testing`, `architecture`.

Read each resolved convention file in full.

### Resolve scope and changed_files

Before spawning any Agent, compute the review scope from `$ARGUMENTS` (after `--dry-run` has been stripped):

1. **Detect PR URL**: if `$ARGUMENTS` contains a GitHub PR URL (e.g. `https://github.com/org/repo/pull/123`), extract `pr_number`:
   ```bash
   pr_number=$(echo "$ARGUMENTS" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')
   ```
   Then treat the input as if the user had passed the bare `pr_number`.

2. **Compute `scope_description`, `diff_text`, and `pr_head_branch`**:
   - **No request or "current branch"** (`$ARGUMENTS` is empty after stripping):
     ```bash
     diff_text=$(git diff $(git merge-base HEAD $(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main))...HEAD)
     scope_description="current branch diff vs origin/HEAD"
     pr_head_branch=""
     ```
   - **PR number** (bare integer or extracted `pr_number`):
     ```bash
     diff_text=$(gh pr diff <pr_number>)
     pr_meta=$(gh pr view <pr_number> --json title,headRefName,baseRefName,author)
     pr_head_branch=$(echo "$pr_meta" | grep -oE '"headRefName":"[^"]*"' | cut -d'"' -f4)
     scope_description="PR <pr_number>"
     ```
   - **File paths or globs**:
     ```bash
     diff_text=$(git diff -- <paths>)
     scope_description="<paths>"
     pr_head_branch=""
     ```
   - **Commit range or other description**: use git to produce the appropriate diff; set `scope_description` to the description; `pr_head_branch=""`.

3. **Compute `changed_files`** from `diff_text`:
   ```bash
   changed_files=$(echo "$diff_text" | grep -E '^diff --git' | sed 's#diff --git a/.* b/##')
   ```
   For file-path inputs where git diff may be empty (e.g. unmodified files explicitly listed), fall back to the literal paths from `$ARGUMENTS`.

4. **Early exit if nothing to review**: if `changed_files` is empty and `diff_text` is empty:
   ```
   STATUS: NOTHING_TO_REVIEW — no changed files found for scope: <scope_description>
   ```
   Print this and stop. Do not spawn any Agent.

### Write temporary build-state.json

`state-ops.sh` requires a `build-state.json` file. Create it now so the complexity-gate sub-skill can run later in the parallel batch.

```bash
temp_state="$project_root/.bf/sessions/build-state.json"
mkdir -p "$project_root/.bf/sessions"
build_ts=$(date -u +%Y%m%dT%H)
slug="review-${timestamp}"
```

**If `$temp_state` already exists**, back it up first:

```bash
temp_state_backup="$temp_state.bfreview-backup"
[ -f "$temp_state" ] && cp "$temp_state" "$temp_state_backup" && \
  echo "Warning: .bf/sessions/build-state.json already exists — a feature workflow may be in progress. Backing it up; it will be restored after the complexity scan."
```

Write the following JSON to `$temp_state`:

```json
{
  "idea": "bf:review complexity scan",
  "slug": "review-<timestamp>",
  "build_timestamp": "<build_ts>",
  "mode": "review",
  "phase": "verify",
  "phase_status": "in_progress",
  "github_issue": {"enabled": false, "number": null},
  "jira": {"enabled": false, "ticket_key": null, "ticket_url": null, "pending_questions": null},
  "collect_todos": null,
  "artifacts": {"spec": null, "plan": null, "todo": null, "backlog": null},
  "created_at": "<iso_now>",
  "updated_at": "<iso_now>"
}
```

**Note**: `state-ops.sh` computes `paths.complexity_report` as `<project_root>/.bf/sessions/<build_ts>-review-<timestamp>-temp.md`. Set `complexity_report_path` to that path.

### Pre-review: check for existing integration/E2E tests

Before spawning the review agent, grep the project for integration and E2E test files:

```bash
int_tests=$(find "$project_root" -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*.e2e.*" \) \
  -not -path "*/.git/*" -not -path "*/node_modules/*" \
  | grep -iE "(integration|e2e|end.to.end)" | head -20)
```

Set:
- `has_integration_tests="yes"` if the command returned any results; `"no"` otherwise.
- `has_e2e_tests="yes"` if any result path contains `e2e` or `end-to-end`; `"no"` otherwise.

### Spawn review + complexity + consistency Agents in parallel (model: opus)

Print (plain text): `→ Reviewing + running complexity + consistency gates with opus… (this usually takes a few minutes)`

Read `${CLAUDE_PLUGIN_ROOT}/skills/feature/complexity-gate/SKILL.md` in full.
Read `${CLAUDE_PLUGIN_ROOT}/skills/feature/consistency-gate/SKILL.md` in full.

Build three prompts:

**Prompt A — review Agent:**

```
You are a code reviewer. Apply the following conventions strictly.

## Dev Convention
<contents of resolved dev.md>

## Testing Convention
<contents of resolved testing.md>

## Architecture Convention
<contents of resolved architecture.md>

## Code Review Convention
<contents of resolved code-review.md>

## Scope

The review scope has already been resolved by the orchestrating skill.

changed_files:
<one path per line from changed_files>

scope_description: <scope_description>

diff_text:
<diff_text>

pr_head_branch: <pr_head_branch if non-empty, else omit>

## Test Coverage Context

Integration tests found in package: <has_integration_tests>
E2E tests found in package: <has_e2e_tests>

Sample paths (up to 20):
<$int_tests if non-empty, otherwise: "(none found)">

When flagging missing integration or E2E tests:
- If `has_integration_tests` is "yes", do NOT flag missing integration tests unless the changed functionality has no integration test coverage at all.
- If `has_e2e_tests` is "yes", do NOT flag missing E2E tests unless the changed functionality has no E2E test coverage at all.
- If both are "no", flag their absence as a `[must-fix]` concern under Testing.

## Instructions

1. The changed files and diff are already provided in the `## Scope` block above — do NOT re-run git or gh to re-derive the scope.
2. Read the full current content of each file listed in `changed_files` using the Read tool before forming conclusions.
3. Apply every check in the Code Review Convention across all five categories.
4. Produce the report in this exact format — including the Review Metadata block at the end:

# Code Review Report
- Scope: <human-readable description of what was reviewed>
- Timestamp: <ISO 8601>
- Files reviewed: <count>

STATUS: PASS | CONCERN

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

<full contents of complexity-gate/SKILL.md>
```

**Prompt C — consistency-gate Agent** (same pattern):

```
## OVERRIDE — changed_files

Do NOT run `changed-packages.sh`. Treat the following paths as `changed_files` instead:

<one path per line from changed_files>

Proceed with scan mode using these paths.

<full contents of consistency-gate/SKILL.md>
```

Dispatch all three Agents in a **single message** (all model: opus), so they run in parallel. Wait for all three to return.

### Clean up temp state

After all three Agents return (whether they succeed or fail):

```bash
rm -f "$temp_state"
[ -f "$temp_state_backup" ] && mv "$temp_state_backup" "$temp_state"
```

**This cleanup must happen on every exit path — including when the review Agent fails — do not skip it.**

## Phase 2 — Aggregate Results

### Save review report and extract metadata

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

**Complexity:** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "$complexity_report_path" --block "## Complexity Report"` to extract the STATUS. If the file does not exist or the Agent failed, continue with: `## Complexity\nSTATUS: UNKNOWN (complexity gate failed — see conversation)`.

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

**Consistency:** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "$complexity_report_path" --block "## Consistency Report"` to extract the STATUS. If the file does not exist or the Agent failed, continue with: `## Consistency\nSTATUS: UNKNOWN (consistency gate failed — see conversation)`.

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

If any C*, X*, or Y* concern exists, set overall STATUS to CONCERN.

Rewrite `$report_path` with the merged content (replace the STATUS line at the top).

### Show summary in conversation

Print:

```
STATUS: <PASS | CONCERN>
Concerns: <N> code (<M> must-fix), <X> complexity, <Y> consistency
Report: <report_path>
```

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

- `none` or empty → print "No fixes requested. Report saved at `<report_path>`." and exit.
- `all` → select all C* and X* concerns.
- `must-fix` → select all concerns labelled `[must-fix]`.
- Space-separated IDs → validate each ID exists in the report.
  - If any ID is unknown, ask once: "Unknown ID(s): <list>. Please re-enter valid IDs from the list above." Re-parse the new answer; if still invalid, treat as `none`.

Set `selected_concerns` to the validated list.

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
<contents of resolved dev.md>

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

## Dev Convention / Testing Convention / Architecture Convention / Code Review Convention
<same convention contents as Phase 1>

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
| `~/.bf` not writable | Fall back to `<project_root>/.bf/sessions/reviews/` for `reports_dir`. Warn the user. |
| Convention file missing (all 3 lookup paths absent) | Print "Convention file not found: <last-looked-up path>. This may be a plugin install issue." and stop. |

### Phase 1 — Review

| Condition | Handling |
|-----------|----------|
| Nothing to review (empty diff, no files match) | Agent returns `STATUS: NOTHING_TO_REVIEW` — print it and exit. |
| `gh` error (not installed, not authenticated, PR not found) | Agent surfaces the error — print it and exit. |

### Phase 2 — Complexity Gate

| Condition | Handling |
|-----------|----------|
| Complexity Agent fails or errors | Append `STATUS: UNKNOWN` block. Do not block the review. |
| `build-state.json` already exists | Back it up, warn the user, restore after scan. |

### Fix phase

| Condition | Handling |
|-----------|----------|
| Fix Agent fails | Inform the user, skip re-review, print original report path only. |
| Re-review finds new concerns not in the original | Include in "remaining" count, label `[new]`. |

### Re-invocation

This skill is stateless — each invocation produces a fresh timestamped report. `latest.md` always points to the most recent report. Previous reports are preserved.
