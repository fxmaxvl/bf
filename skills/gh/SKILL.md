---
name: gh
description: Create GitHub issues, pick existing ones to work on, or verify whether an issue is still actual. Auto-generates titles/labels for new issues, classifies existing ones, and kicks off feature.
argument-hint: [optional: "pick", "pick bug", issue URL/number + "verify", or issue description]
model: sonnet
---
Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Manage GitHub issues on the current repository. Three modes: **create** (capture something to track), **pick** (select an existing issue to work on), and **verify** (check whether an issue's items are still open and hand off any that are).

## Mode Detection

Determine the mode from `$ARGUMENTS` and conversation context:

- **Verify mode**: `$ARGUMENTS` contains an issue URL or number AND at least one of: "verify", "check", "audit", "still actual", "still relevant", "is this still open"
- **Pick mode**: User says things like "pick", "let's pick a bug", "what do we have", "let's see issues", "find something to work on"
- **Create mode**: Everything else — user describes a problem, or invoked mid-conversation to capture something

---

## Shared: Detect the Repository

Run `git remote get-url origin` to get the remote URL. Extract the `owner/repo` from it.
If no git remote is found, stop and tell the user.

---

## Verify Mode

**This mode is read-only against the codebase.** Do not apply any fixes or write any code here. If work is needed, it MUST be routed through feature/quick via the handoff step below.

### 1. Fetch the issue

Extract the issue number from `$ARGUMENTS` (from a URL like `https://github.com/owner/repo/issues/42` or a bare number). Run:

```
gh issue view <number> --repo <owner/repo> --json number,title,body,state,labels
```

If the issue is already closed, tell the user and stop.

### 2. Extract items

Parse the issue body into a list of discrete items. Issues often contain bullet points, numbered lists, or `##` sub-sections — treat each as a separate item. If the body is a single block of prose with no list structure, treat it as one item.

### 3. Check each item against the codebase

For each item, read the relevant files (use Grep/Read/Glob) to determine its current status:

- **Resolved** — the code already addresses the item fully
- **Partial** — the code addresses part of the item but something remains
- **Open** — no change found; the item is still relevant

Do not make assumptions — verify by reading the actual files. Cite the file and line for resolved/partial findings.

### 4. Report findings

Present a concise table:

```
| # | Item (summary) | Status | Evidence |
|---|----------------|--------|----------|
| 1 | <short summary> | Resolved | <file:line> |
| 2 | <short summary> | Open | — |
| 3 | <short summary> | Partial | <file:line> |
```

For any resolved items, post a comment on the issue noting what addressed them:

```
gh issue comment <number> --repo <owner/repo> --body "<comment>"
```

### 5. Handle open/partial items

If all items are resolved: tell the user, close the issue (`gh issue close <number> --repo <owner/repo>`), and stop.

If any items are open or partial: ask "Want to work on these? (full workflow / quick mode / skip)"

- **Skip**: stop here.
- **Full or quick**: proceed to the handoff below.

### 6. Handoff to feature/quick

1. Get the current GitHub user: `gh api user --jq '.login'`
2. Assign the issue: `gh issue edit <number> --repo <owner/repo> --add-assignee <login>`
3. Synthesize a description containing **only the open/partial items** (not the resolved ones), prefixed with `GH-ISSUE:<number>`:

```
GH-ISSUE:<number> <issue title>

<open/partial item 1 — full text>

<open/partial item 2 — full text>
```

4. Invoke `feature` (full workflow) or `quick` (quick mode) with this synthesized description.

---

## Create Mode

### 1. Generate issue content

From the conversation context (or `$ARGUMENTS` if provided), generate:

- **Title**: Use a conventional-style category prefix followed by a concise description. Prefixes describe the category of the issue, not an action:
  - `bug:` — something is broken
  - `feat:` — a feature request or idea
  - `refactor:` — code improvement without behavior change
  - `docs:` — documentation gap or improvement
  - `chore:` — maintenance, dependencies, tooling
  - `perf:` — performance issue
  - Other prefixes are fine if they fit — keep it open-ended
- **Label**: Pick a label that matches the category (e.g., `bug`, `feature`, `refactoring`, `documentation`, `chore`, `performance`). Use whatever label name feels right for the context — not restricted to a fixed set.
- **Description**: A clear, concise description of the issue. Include relevant context from the conversation. Use markdown formatting.

### 2. Show draft for approval

Present the draft to the user:

```
Title: <title>
Label: <label>
---
<description>
```

Ask: "Create this issue? (or suggest changes)"

### 3. Create the issue

On approval:

1. Check if the label exists on the repo. If not, create it using `gh label create "<label>" --repo <owner/repo>`.
2. Create the issue using `gh issue create --repo <owner/repo> --title "<title>" --label "<label>" --body "<description>"`.
3. Return the issue URL to the user.

---

## Pick Mode

### 1. Fetch open issues

Run `gh issue list --repo <owner/repo> --state open --limit 50 --json number,title,labels,body,assignee` to get the list of open issues.

If no open issues exist, tell the user.

### 2. Classify issues

For each issue, determine its type — even if it has no labels or doesn't follow our naming conventions. Read the title and body to infer the category:

- `bug` — describes something broken, an error, unexpected behavior
- `feature` — describes a request, idea, enhancement
- `refactoring` — describes code cleanup, restructuring
- `docs` — describes missing or incorrect documentation
- `chore` — describes maintenance, dependency updates, tooling
- `perf` — describes a performance problem
- Other categories as appropriate

### 3. Present issues

If the user asked for a specific type (e.g., "pick a bug"), filter to that type. Otherwise show all.

Present issues grouped by inferred type in a readable format:

```
### bug
- #12: Token refresh fails on expired sessions
- #8: CSS grid overlap on mobile

### feature
- #15: Add dark mode support
- #3: Export to CSV

### chore
- #11: Upgrade dependencies
```

Ask: "Which issue do you want to pick up?"

### 4. Pick and assign

When the user picks an issue:

1. Get the current GitHub user with `gh api user --jq '.login'`.
2. Assign the issue to them: `gh issue edit <number> --repo <owner/repo> --add-assignee <login>`.
3. Get the full issue details (title, body, number) to pass to feature.

### 5. Choose mode

Ask: "Full workflow (brainstorm → spec → review → plan → execute) or quick mode (refine → plan → execute)?"

### 6. Kick off feature

Invoke `feature` or `quick` based on the user's choice. Pass a synthesized description that includes:

- A `GH-ISSUE:<number>` marker so feature can detect the GitHub issue (e.g., `GH-ISSUE:12`)
- The issue title
- The issue body/description

Example `$ARGUMENTS` for feature:
```
GH-ISSUE:12 Token refresh fails on expired sessions

Session tokens are not being refreshed when they expire, causing 401 errors...
```

This gives feature the full context to start the brainstorm phase and track the issue through to PR creation.

---

## Notes

- When invoked mid-conversation in create mode, synthesize the issue from discussion context — the user should not need to re-explain.
- Keep titles short (under 80 chars) in create mode.
- In pick mode, classification should be best-effort — it's fine to mark ambiguous issues as their best guess.
- If `$ARGUMENTS` is provided and clearly a create request, use it as the primary source for the issue content.
