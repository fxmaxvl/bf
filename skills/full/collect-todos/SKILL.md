---
name: collect-todos
description: Scan implementation changes for TODO comments and generate a backlog document.
disable-model-invocation: true
allowed-tools: Read, Write, Grep, Glob, Bash(git *)
model: sonnet
---

Scan the feature branch changes for `TODO` comments **that are related to this feature**. Ignore pre-existing TODOs that were not introduced or modified by this branch.

## Input

Run the helper scripts. Use Glob to find them: `~/.claude/skills/bfeature-full/scripts/`.

```
bash "$(find ~/.claude -name state-ops.sh -path '*/full/scripts/*' 2>/dev/null | head -1)"
bash ~/.claude/skills/bfeature-full/scripts/changed-packages.sh
```

`state-ops.sh` gives you `slug`, `build_timestamp`, `mode`, and artifact paths.
`changed-packages.sh` gives you `changed_files` — use this list to scope TODO detection.

Read the appropriate feature context for filtering relevant TODOs:
- **Full mode** (`mode` = `"full"`): Read the path at `paths.spec` from `state-ops.sh` output.
- **Quick mode** (`mode` = `"quick"`): Read the path at `paths.qa` from `state-ops.sh` output.

## Steps

### 1. Find TODOs introduced by this branch

Use `git diff master...HEAD` to get the actual diff. Only consider lines that were **added or modified** by this branch (lines starting with `+` in the diff). Cross-reference against `changed_files` from `changed-packages.sh` to confirm scope. This ensures pre-existing TODOs in touched files are excluded.

Search the added/modified lines for `TODO` comments (case-insensitive).

For each match, capture:
- **File path** and **line number**
- **Comment text** (the rest of the line after `TODO`)
- **Context** — the surrounding code (2 lines above and below)

### 2. Assess feature relevance

Every TODO found in step 1 should be included — never silently drop items. Assess whether each TODO is clearly related to the feature:

- **Clearly related** — has `(<slug>)` tag (e.g., `TODO(<slug>):`), or clearly references the feature's domain, components, or describes workarounds made during this implementation. Use the slug as the Feature value.
- **Unclear** — untagged and the connection to the feature is ambiguous. Could be a drive-by improvement or generic note. Prefix the Feature value with `[?]` so the user can decide.

### 3. Classify each item

For each found comment, classify the reason:
- **temporary-solution** — workaround that should be replaced with a proper implementation
- **dependency-limitation** — waiting for better support from a dependency
- **incomplete** — feature-related work that was deferred
- **tech-debt** — code quality issue acknowledged but not addressed

### 4. Generate backlog document

Write to `.claude/.bfeature-temp/<build_timestamp>-<slug>-backlog.md`. The file contains **only** a markdown table — no title, no header, no prose. See `example-dark-mode-backlog.md` in this skill's directory for the exact format.

Key rules:
- The `Feature` column contains the slug. Prefix with `[?]` when relevance to the feature is unclear.
- The `Location` column uses `file:line` format (e.g., `src/foo.ts:42`).
- This format is designed to be mergeable across features — multiple backlog files can be concatenated.

### 5. Report

- If **no items found**: tell the user "No TODOs or workarounds found in the implementation. Clean!"
- If **items found**: tell the user how many were found, show the summary table, and confirm the backlog was saved

## Output

- Backlog document: write to the path at `paths.backlog` from `state-ops.sh` output.
- Update `.claude/.bfeature-temp/build-state.json`: set `artifacts.backlog` to `"<build_timestamp>-<slug>-backlog.md"`
