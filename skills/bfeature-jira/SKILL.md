---
name: jira-issue
model: sonnet
description: Pick Jira tickets to work on or interact with them (read, transition, comment). Discovers Jira MCP tools dynamically.
argument-hint: [optional: "pick", "pick PROJECT", or Jira ticket URL]
---

Manage Jira tickets. Two modes: **pick** (browse and select a ticket to work on) and **url** (pass a specific ticket URL). Also provides utility operations used by other skills.

## Tool Discovery

Jira MCP tool names vary by user setup. The namespace prefix is not predictable.

**On first use**, discover the available Jira tools:
1. Look at the available tools list for any tool whose name contains `jira` and ends with `get-issues`
2. From the matched tool name, extract the full prefix (everything before `get-issues`)
3. If no Jira tools are found, report: "No Jira MCP tools available. Please configure a Jira MCP server and try again."

Once the prefix is known, the following operations map to these tool suffixes:
- **get-issues** — fetch ticket details (description, comments, status)
- **get-available-transitions** — list valid status transitions for a ticket
- **transition-issue** — move a ticket to a new status
- **comment-on-issue** — add a comment to a ticket
- **get-issue-changelog** — view ticket history
- **get_user** — get current user info

## Mode Detection

Determine the mode from `$ARGUMENTS`:

- **Pick mode**: Arguments are empty, "pick", or "pick PROJECT-KEY" (e.g., "pick INGEST")
- **URL mode**: Arguments contain a Jira ticket URL (e.g., `https://<domain>.atlassian.net/browse/PROJ-123`)

---

## Pick Mode

### 1. Get current user

Call `<prefix>get_user` to get the current Jira user's account ID and display name.

### 2. Fetch open tickets assigned to me

Use `<prefix>get-issues` with a JQL query to fetch open tickets assigned to the current user, ordered by priority:

- **Default (no project specified):** `assignee = currentUser() AND status != Done ORDER BY priority DESC`
- **With project filter** (e.g., "pick INGEST"): `assignee = currentUser() AND project = INGEST AND status != Done ORDER BY priority DESC`

### 3. Classify and present tickets

For each ticket, determine its type from the issue type, title, and description:

- `bug` — bug reports, defects, errors
- `feature` — stories, feature requests, enhancements
- `task` — generic tasks, chores
- `improvement` — improvements, optimizations
- Other categories as appropriate based on Jira issue type

Present tickets grouped by type, showing priority and status:

```
### bug (High priority)
- PROJ-45: Token refresh fails on expired sessions [In Review]
- PROJ-32: CSS grid overlap on mobile [To Do]

### feature
- PROJ-51: Add dark mode support [To Do]
- PROJ-23: Export to CSV [To Do]

### task
- PROJ-40: Upgrade dependencies [To Do]
```

Ask: "Which ticket do you want to pick up?"

### 4. Pick and start

When the user picks a ticket:

1. Read the full ticket details with `read-ticket(ticket_key)` (see Operations below)
2. Transition the ticket to "In Progress": `transition-to(ticket_key, "In Progress")`
3. Kick off the `bfeature-full` skill with the ticket context

### 5. Choose mode

Ask: "Full workflow (brainstorm → spec → review → plan → execute) or quick mode (refine → plan → execute)?"

### 6. Kick off bfeature

Invoke `bfeature-full` or `bfeature-quick` based on the user's choice. Pass a synthesized description that includes:

- The Jira ticket URL so bfeature can detect it (e.g., `https://<domain>.atlassian.net/browse/PROJ-45`)
- The ticket title/summary
- The ticket description/body

Example `$ARGUMENTS` for bfeature:
```
https://<domain>.atlassian.net/browse/PROJ-45 Token refresh fails on expired sessions

Session tokens are not being refreshed when they expire, causing 401 errors...
```

This gives bfeature the full context to start the brainstorm phase and track the ticket through to PR creation.

---

## URL Mode

When a Jira ticket URL is passed directly:

1. Extract the ticket key from the URL (e.g., `PROJ-123` from `https://domain.atlassian.net/browse/PROJ-123`)
2. Read the full ticket details with `read-ticket(ticket_key)`
3. Transition to "In Progress": `transition-to(ticket_key, "In Progress")`
4. Ask: "Full workflow (brainstorm → spec → review → plan → execute) or quick mode (refine → plan → execute)?"
5. Kick off `bfeature-full` or `bfeature-quick` based on the user's choice, with the ticket context (same format as Pick Mode step 6)

---

## Operations

These operations are also used by other skills (e.g., `bfeature`) when they need to interact with Jira tickets.

### `read-ticket(ticket_key)`
1. Call `<prefix>get-issues` with the ticket key
2. Return the ticket's summary, description, comments, and current status

### `transition-to(ticket_key, target_status_name)`
1. Call `<prefix>get-available-transitions` for the ticket
2. Find the transition whose target status name matches `target_status_name` (case-insensitive, partial match OK — e.g., "in progress" matches "In Progress")
3. If no match found, list the available transitions and ask the user which one to use
4. Call `<prefix>transition-issue` with the matched transition ID

### `add-comment(ticket_key, comment_body)`
1. Call `<prefix>comment-on-issue` with the ticket key and comment body

### `ask-author(ticket_key, questions)`
1. Call `<prefix>get-issues` with the ticket key to identify the ticket's reporter/author
2. Format the comment: tag the author (mention them) and list the clarifying questions
3. Call `<prefix>comment-on-issue` with the formatted comment

### `check-for-answers(ticket_key, pending_questions)`
1. Call `<prefix>get-issues` with the ticket key to fetch the latest comments
2. Look for new comments added after the questions were posted
3. Try to match answers to the pending questions
4. Return which questions were answered (with the answers) and which are still pending

## Error Handling

- If a Jira API call fails, report the error clearly and ask the user how to proceed
- Never silently skip a Jira operation — the user needs to know if their ticket wasn't updated
