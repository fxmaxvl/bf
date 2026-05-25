---
name: scan-conventions
description: Use when you need to discover and apply user-defined custom conventions relevant to the current task. Invoke before acting on any task where project- or user-level convention files beyond the predefined set (dev, testing, git, architecture, typescript, code-review) might apply.
model: sonnet
disable-model-invocation: false
argument-hint: "[task description]"
allowed-tools: Read, Bash(git *), Bash(ls *), Bash(cat *), Bash(find *), Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Discover user-defined custom convention files from project and user tiers, then filter to those relevant to the current task. Works standalone (`/bf:scan-conventions [task description]`) or as a helper called by other bf skills.

## On Invocation

Print banner (plain text):

```
── bf:scan-conventions ──────────────────────────────
```

Set `DISCOVER_SCRIPT=${CLAUDE_PLUGIN_ROOT}/skills/scan-conventions/scripts/discover-conventions.sh`.

Determine task context:
- If an argument was passed, use it as `TASK_DESCRIPTION`.
- Otherwise run `git log -1 --pretty=%B 2>/dev/null` and `git diff --name-only HEAD 2>/dev/null` to infer context. If git is unavailable, set `TASK_DESCRIPTION=""`.

## Phase 1 — Discover

Run:

```bash
bash "$DISCOVER_SCRIPT"
```

Parse the JSON array output. Each entry: `{filename, tier, first_heading, path}`.

If the array is empty → print:

```
No custom conventions found in project or user tiers.
```

…and exit cleanly with an empty result.

## Phase 2 — Filter by Relevance

For each discovered file:

1. Read the file content.
2. Decide whether it is relevant to `TASK_DESCRIPTION`. Relevant means: the convention would meaningfully constrain or guide behaviour for this specific task. When `TASK_DESCRIPTION` is empty, include all files (no context to filter against).
3. If relevant, record `{filename, path, tier, relevance_reason}`.

## Phase 3 — Output

Print the result as a structured block:

```
### Custom Conventions

Relevant ({N} of {total} scanned):

- **{filename}** ({tier}) — {relevance_reason}
  Path: {path}
```

If no files matched after filtering:

```
### Custom Conventions

No custom conventions matched the current task.
```

For **standalone use**: this output is the final deliverable. Read each relevant file and apply its rules to subsequent work in this session.

For **helper use** (called by another skill): return the structured block so the caller can read the listed paths and apply the conventions.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `discover-conventions.sh` exits non-zero | Print warning with error output; treat as empty result and continue. |
| No git repo in cwd | Script falls back to empty `PROJECT_ROOT`; only user tier (`~/.bf/conventions/`) is scanned. |
| `python3` not in PATH | Print warning "discovery script requires python3"; treat as empty result. |
| Convention file is unreadable | Skip it; note filename in output as "(unreadable — skipped)". |
| No task description and git context empty | Include all discovered files (no filter applied). |
| Same filename in both tiers | Project tier wins (handled by script via dedup). |
