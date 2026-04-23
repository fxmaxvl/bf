---
name: gh
description: Create GitHub issues or pick existing ones to work on. Auto-generates titles/labels for new issues, classifies existing ones, and kicks off bfeature.
argument-hint: [optional: "pick", "pick bug", or issue description]
model: sonnet
---
Manage GitHub issues on the current repository. Two modes: **create** (capture something to track) and **pick** (select an existing issue to work on).

## Mode Detection

Determine the mode from `$ARGUMENTS` and conversation context:

- **Pick mode**: User says things like "pick", "let's pick a bug", "what do we have", "let's see issues", "find something to work on"
- **Create mode**: Everything else — user describes a problem, or invoked mid-conversation to capture something

---

## Shared: Detect the Repository

Run `git remote get-url origin` to get the remote URL. Extract the `owner/repo` from it.
If no git remote is found, stop and tell the user.

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
3. Get the full issue details (title, body, number) to pass to bfeature.

### 5. Choose mode

Ask: "Full workflow (brainstorm → spec → review → plan → execute) or quick mode (refine → plan → execute)?"

### 6. Kick off bfeature

Invoke `bfeature-full` or `bfeature-quick` based on the user's choice. Pass a synthesized description that includes:

- A `GH-ISSUE:<number>` marker so bfeature can detect the GitHub issue (e.g., `GH-ISSUE:12`)
- The issue title
- The issue body/description

Example `$ARGUMENTS` for bfeature:
```
GH-ISSUE:12 Token refresh fails on expired sessions

Session tokens are not being refreshed when they expire, causing 401 errors...
```

This gives bfeature the full context to start the brainstorm phase and track the issue through to PR creation.

---

## Notes

- When invoked mid-conversation in create mode, synthesize the issue from discussion context — the user should not need to re-explain.
- Keep titles short (under 80 chars) in create mode.
- In pick mode, classification should be best-effort — it's fine to mark ambiguous issues as their best guess.
- If `$ARGUMENTS` is provided and clearly a create request, use it as the primary source for the issue content.
