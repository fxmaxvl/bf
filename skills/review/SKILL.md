---
name: review
description: Review code (current branch diff, a PR by number, or specific files) against bfeature code-review conventions and the complexity gate.
model: opus
disable-model-invocation: false
argument-hint: "[empty | PR number | file paths]"
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), Bash(mkdir *), Bash(ln *), Bash(date *), Bash(sha1sum *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill, including the **one-question-per-turn** rule that applies at every interactive point in this skill.

## On Invocation

### Detect scope from `$ARGUMENTS`

```
if [ -z "$ARGUMENTS" ]; then
  scope=branch
elif echo "$ARGUMENTS" | grep -qE '^\s*[0-9]+\s*$'; then
  scope=pr
  pr_number=$(echo "$ARGUMENTS" | tr -d ' ')
else
  scope=files
  file_paths="$ARGUMENTS"
fi
```

### Verify git repo

Run: `git rev-parse --show-toplevel`

If this fails, print: "Not a git repository. Exiting." and stop.

Set `project_root` to the output.

### Compute project_id and report paths

Derive project_id from the git remote URL (same derivation used in `~/.vs/` artifacts elsewhere):

```bash
PROJECT_ID=$(git config --get remote.origin.url 2>/dev/null \
  | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$project_root")
```

Set paths:

```bash
timestamp=$(date -u +%Y%m%dT%H%M%S)
reports_dir="$HOME/.vs/$PROJECT_ID/reviews"
scope_label=<branch | pr-<pr_number> | files>
report_path="$reports_dir/${timestamp}-${scope_label}-review.md"
complexity_report_path="$reports_dir/${timestamp}-${scope_label}-complexity.md"
```

Create the reports directory: `mkdir -p "$reports_dir"`

### Print banner

```
── bf:review | <Scope> ───────────────────────────────
```

Where `<Scope>` is one of: `Branch`, `PR #<n>`, or `Files: <list>`.

Print as plain text, not in a code block.

## Phase 1 — Collect

### Branch scope

```bash
default_remote_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)
base=$(git merge-base HEAD "$default_remote_branch")
diff_text=$(git diff "$base"...HEAD)
changed_files=$(git diff --name-only "$base"...HEAD)
```

If `diff_text` is empty: print "Branch has no changes vs base. Nothing to review." and exit.

### PR scope

1. Verify `gh` is installed: `gh --version`. If it fails, print "gh is not installed. Install it from https://cli.github.com and run `gh auth login`." and exit.
2. Verify auth: `gh auth status`. If it fails, print "gh is not authenticated. Run `gh auth login` and retry." and exit.
3. Collect:

```bash
diff_text=$(gh pr diff "$pr_number")
changed_files=$(gh pr view "$pr_number" --json files --jq '.files[].path')
pr_meta=$(gh pr view "$pr_number" --json title,headRefName,baseRefName,author)
```

If `gh pr diff` fails (e.g. PR not found), surface the gh error message and exit.

### Files scope

1. Validate each path exists and is tracked:

```bash
git ls-files --error-unmatch $file_paths
```

If any path is not tracked, list the missing paths and exit.

2. Collect:

```bash
diff_text=$(git diff -- $file_paths)
# If diff is empty (clean working tree), use full file content instead
if [ -z "$diff_text" ]; then
  # Read each file in full — use the Read tool for each path
fi
changed_files="$file_paths"
```

### After collection

`diff_text` and `changed_files` are now available for the review and complexity agents.

## Phase 2 — Review

### Resolve conventions

Resolve each convention using the 3-step lookup from `plugin-main.md`:

1. `<project_root>/.claude/bf-conventions/<name>.md`
2. `~/.claude/bf-conventions/<name>.md`
3. `${CLAUDE_PLUGIN_ROOT}/conventions/<name>.md`

Resolve: `code-review`, `dev`, `testing`, `architecture`.

Read each resolved convention file in full.

### Spawn review Agent (model: opus)

Read the resolved convention files and pass their full contents to an Agent with the following prompt:

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
<scope label — branch / PR #N / files>
<pr_meta JSON if PR scope, omit otherwise>

## Changed Files
<one path per line from changed_files>

## Diff
<diff_text>

## Instructions

1. Read the full content of each changed file (not just diff hunks) using the Read tool before forming conclusions.
2. Apply every check in the Code Review Convention across all five categories.
3. Produce the report in this exact format:

# Code Review Report
- Scope: <branch | PR #N | files: <list>>
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
Return only the report — no preamble or commentary.
```

### Save initial report

Write the Agent's output to `$report_path`.

Update the symlink: `ln -sf "$report_path" "$reports_dir/latest.md"`

## Phase 3 — Complexity Gate

### Write temporary build-state.json

Create the temp state so `state-ops.sh` works when invoked by the complexity-gate sub-skill:

```bash
temp_state="$project_root/.claude/.bfeature-temp/build-state.json"
mkdir -p "$project_root/.claude/.bfeature-temp"
```

Write the following JSON to `$temp_state`:

```json
{
  "slug": "review-<timestamp>",
  "mode": "review",
  "phase": "verify",
  "paths": {
    "complexity_report": "<complexity_report_path>"
  }
}
```

Where `<timestamp>` and `<complexity_report_path>` use the values computed in "On Invocation".

Also write a newline-separated list of changed files to `$project_root/.claude/.bfeature-temp/changed-files.txt` (one path per line). This is used by `changed-packages.sh`.

### Invoke complexity-gate Agent (model: opus)

Read `${CLAUDE_PLUGIN_ROOT}/skills/bfeature/complexity-gate/SKILL.md` in full and pass its contents as the Agent prompt with model: opus.

The sub-skill will re-run `state-ops.sh` and `changed-packages.sh` internally, discover the changed files, scan for complexity red flags, and write its report to `paths.complexity_report`.

### Clean up temp state

After the complexity Agent returns (whether it succeeds or fails), delete the temp files:

```bash
rm -f "$temp_state"
rm -f "$project_root/.claude/.bfeature-temp/changed-files.txt"
```

**This cleanup must happen on every exit path — do not skip it.**

### Merge complexity findings into report

Read `$complexity_report_path`. If the file does not exist or the Agent failed, continue with a note: `## Complexity\nSTATUS: UNKNOWN (complexity gate failed — see conversation)`.

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

### Escalate overall STATUS

If any C* or X* concern exists (regardless of label), set overall STATUS to CONCERN.

Rewrite `$report_path` with the merged content (replace the STATUS line at the top).

### Show summary in conversation

Print:

```
STATUS: <PASS | CONCERN>
Concerns: <N> code (<M> must-fix), <X> complexity
Report: <report_path>
```

## Phase 4 — Fix Selection

**One-question-per-turn rule applies in this phase.** Ask step 1 and wait for the answer before asking step 2. Never batch both into one message.

### If STATUS is PASS

Print: "No concerns found. Report saved at `<report_path>`." and exit.

### If STATUS is CONCERN

**Step 1 — Selection question**

Print a one-line summary of each concern:

```
C1 [must-fix]       src/foo.ts:42 — <problem description>
C2 [should-consider] src/bar.ts:8 — <problem description>
X1 [must-fix]       src/baz.ts:15 — <complexity finding>
```

Then ask (one question only):

> Which concerns would you like to fix? Reply with IDs (e.g. `C1 C3 X1`), `all`, `must-fix`, or `none`.

Wait for the user's reply before proceeding.

**Parse the answer:**

- `none` or empty → print "No fixes requested. Report saved at `<report_path>`." and exit.
- `all` → select all C* and X* concerns.
- `must-fix` → select all concerns labelled `[must-fix]`.
- Space-separated IDs (e.g. `C1 C3 X1`) → validate each ID exists in the report.
  - If any ID is unknown, ask once: "Unknown ID(s): <list>. Please re-enter valid IDs from the list above." Then re-parse the new answer; if still invalid, treat as `none`.

Set `selected_concerns` to the validated list.

**Step 2 — Confirmation question**

Print: "Will fix: <selected IDs>. Proceed? (yes/no)"

Wait for reply.

- `yes` (or `y`) → proceed to Phase 5.
- anything else → return to Step 1 (re-ask the selection question).

## Phase 5 — Fix

### Spawn fix Agent (model: sonnet)

Collect the selected concerns from the report: extract the full description blocks for each selected ID (including `file:line`, problem, and suggested fix).

Pass the following prompt to an Agent with model: sonnet:

```
You are applying code fixes identified by a code review.

## Dev Convention
<contents of resolved dev.md>

## Selected Concerns
<concern block for each selected ID, preserving full text>

## Diff Context
<diff_text from Phase 1>

## Changed Files
<one path per line>

## Instructions

- Apply each fix in place, editing the actual source files.
- Do not modify any file outside the changed_files list.
- Do not commit or push anything.
- For PR scope: fixes apply to the local working tree.
- If a fix cannot be applied cleanly (e.g. the code has moved), add a TODO comment at the relevant location:
  `// TODO(bf:review): <concern ID> — <brief description of what needs manual fixing>`
- Do not add explanatory text to the source files; only the necessary code changes and TODO markers.
- Return a brief summary: which concerns were applied, which were deferred with a TODO.
```

### Re-review cycle

After the fix Agent returns, run Phase 2 again (review Agent, same scope) scoped to `changed_files`. This is re-review cycle 1.

**Cap at 2 re-review cycles.** Do not run a third fix→review round regardless of remaining concerns.

Set `after_fix_report_path` to `${report_path%.md}-after-fix.md` (or `-after-fix-2.md` for cycle 2).

Save the new review report to `after_fix_report_path`. Update `latest.md` symlink.

**Do not overwrite the original `$report_path`.** Preserve it as the baseline.

### Tell the user

After the final re-review, print:

```
Original report:  <report_path>
After-fix report: <after_fix_report_path>
Resolved:  <N> concerns addressed
Remaining: <M> concerns still present
```

If remaining concerns exist, list them by ID and label (same one-line format as Phase 4 Step 1) so the user knows what was not resolved.

## Edge Cases & Errors

### Startup

| Condition | Handling |
|-----------|----------|
| Not a git repository | Print "Not a git repository. Exiting." and stop. |
| `~/.vs` not writable | Fall back to `<project_root>/.claude/.bfeature-temp/reviews/` for `reports_dir`. Warn: "~/.vs not writable — saving reports to <fallback_path>." |
| Convention file missing (all 3 lookup paths absent) | Print "Convention file not found: <last-looked-up path>. This may be a plugin install issue." and stop. |

### Phase 1 — Collect

| Condition | Handling |
|-----------|----------|
| Branch scope, empty diff | Print "Branch has no changes vs base. Nothing to review." and exit cleanly. |
| `gh` not installed (PR scope) | Print "gh CLI is not installed. Install it from https://cli.github.com and run `gh auth login`." and exit. |
| gh not authenticated (PR scope) | Print "gh is not authenticated. Run `gh auth login` and retry." and exit. |
| PR not found | Surface the gh error message verbatim and exit. |
| Files scope — one or more paths not tracked | List the untracked paths: "The following paths are not tracked by git: <list>. Verify paths and retry." and exit. |

### Phase 3 — Complexity Gate

| Condition | Handling |
|-----------|----------|
| Complexity Agent fails or errors | Continue with review report. Append `## Complexity\nSTATUS: UNKNOWN (complexity gate failed — see conversation)` to the report. Do not block the review. |
| Temp `build-state.json` already exists (another bfeature run in progress) | Print "Warning: .bfeature-temp/build-state.json already exists — a bfeature workflow may be in progress. Overwriting for complexity scan; it will be restored on cleanup." Then proceed normally and restore the original file after the Agent returns. |

### Fix phase

| Condition | Handling |
|-----------|----------|
| Fix Agent fails | Inform the user, skip the re-review, and print the original report path only. |
| Re-review returns a report with new concerns not in the original | Include them in the "remaining" count but label them `[new]` so the user can distinguish. |

### Re-invocation

This skill is stateless — each invocation produces a fresh timestamped report. `latest.md` always points to the most recent report from the current session. Previous reports are preserved.