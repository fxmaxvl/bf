---
name: session-summary
description: Create a summary of the current session with efficiency insights and observations, and check where a hook could have caught a problem.
model: sonnet
disable-model-invocation: true
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(mkdir *), WebFetch(domain:code.claude.com)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

On invocation, print this banner as plain text (not in a code block) before doing any other work:

```
── bf:session-summary ──────────────────────────────────
```

## Step 1 — Write the session summary

Resolve the artifact root, then write the summary to `$SESSIONS_DIR/session_{slug}_{timestamp}.md`. Use the repo only when `.bf/sessions` is git-ignored, so the summary never shows up in it. The probe names a path inside the directory because a `dir/` pattern does not match a directory that does not exist yet.

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$PROJECT_ROOT" ] && git -C "$PROJECT_ROOT" check-ignore -q .bf/sessions/probe; then
  SESSIONS_DIR="$PROJECT_ROOT/.bf/sessions"
else
  SESSIONS_DIR="$HOME/.bf/sessions"
fi
mkdir -p "$SESSIONS_DIR"
```

Include:

- A brief recap of key actions.
- Total cost of the session, only if the harness shows it. It usually does not, in which case write "not available" and move on. Never estimate or infer a figure.
- Efficiency insights.
  - Was any tool output filtered or summarised by a wrapper, and did a decision depend on it?
- Possible process improvements.
- Any other interesting observations or highlights.

## Step 2 — Surface skill/flow improvement candidates

After writing the file, review the session for insights that are **generalizable to the skill or workflow itself** — not specific to this session's content or cost numbers.

Ask yourself: "Would this observation apply to any user of this skill, not just this session?"

Good candidates:
- A skill step that was confusing, redundant, or missing
- A flow that could handle an edge case better
- A convention or instruction that was unclear
- A bug class that a hunt skill flagged as not covered by any of its lenses (a `Lens suggestion:` line from bf:bug-hunt)

Not candidates:
- Session-specific details (cost, what we built today)
- Observations about the user's project or code

### Hook lens

An instruction the model must remember fails in long sessions. A hook runs each time its event fires. So for each problem the session hit, ask: "Could a hook have caught or prevented this, without the model remembering?" Look for:

- A correction the user or a reviewer made more than once
- A rule in a skill or convention that the model forgot
- A manual step repeated by hand, such as a reinstall or a re-check
- A wasted turn, such as a forced continuation or a duplicate notification

Propose a hook only when its check is mechanical: a path, a command pattern, a field in the hook input, a lint result. A judgment call stays in the skill text. For each hook idea, name the event, what it checks, and whether it blocks or only advises. Name a matcher only when the event takes one. Prefer advice. A hook should block only when a miss is worse than a false block.

Pick the event from the hooks reference at https://code.claude.com/docs/en/hooks, for example `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `SessionStart`, `PreCompact` or `Notification`. The list is not complete, and some events take no matcher. Fetch the reference only when a hook idea needs an event, an input field or a snippet that you have not checked yet in this run. Never write an event name or a field from memory.

Before you propose a hook, check the hooks already in force. Read only the `hooks` key of each of these files that exists: `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json`, `~/.claude/settings.json`, and the project's `.claude/settings.json` and `.claude/settings.local.json`. A settings file can hold tokens, so never copy any other value from it into the summary or the issue. A hook that is already in force is not a new idea. If it ran and still missed the problem, propose a fix to that hook instead.

Sort each hook idea, including a fix to a hook in force:

- **bf hook candidate**: it helps any bf user, for example a check on a bf script, a bf workflow step, or a fix to a hook in bf's `hooks/hooks.json`. It joins the Step 3 candidates with a `hook:` prefix.
- **Setup hook**: it fits only this user's tools, commands or repos, or it fixes a hook in the user's own settings. It is not a Step 3 candidate. Append it to the summary file under a `## Hooks for your setup` section, with a `settings.json` snippet. List it only, never install it, and never put it in the GitHub issue.

## Step 3 — Propose a GitHub issue

The candidates are the Step 2 insights and the bf hook candidates. Setup hooks are never candidates. If you found any candidates, present them all as a bulleted list and ask:

> "Want me to file these as a single GitHub issue on `fxmaxvl/bf`? (yes/no)"

If the user says yes, create one consolidated issue. The pre-approval in `allowed-tools` clears when the user answers, so Claude Code asks for permission before `gh issue create` runs. That prompt is expected, and it is the right check before a public post.

```
gh issue create \
  --repo fxmaxvl/bf \
  --title "Skill improvement suggestions from session" \
  --label "enhancement" \
  --body "..."
```

The body should list each insight as a bullet point, written as a general improvement suggestion (no session-specific details). Keep each point concise and actionable. Start a hook candidate with `hook:` and name its event, matcher and check.


---

## Edge Cases & Errors

| Condition | Handling |
|---|---|
| Neither `<project_root>/.bf/` nor `~/.bf/` is writable | Print the summary to the conversation, including any `## Hooks for your setup` section, and say it could not be persisted. Never drop it silently. |
| Not in a git repository | Use the `~/.bf/sessions` fallback; the summary does not need a repo. |
| In a git repo, but `.bf/sessions` is not git-ignored | Use the `~/.bf/sessions` fallback, so the summary does not show up in the repo. |
| The session has nothing worth summarizing | Say so in one line and write nothing rather than padding a file. |
| `gh issue create` fails or `gh` is unauthenticated | Keep the written summary, report the failure, and print the issue body so the user can file it by hand. |
| The user declines the improvement issue | Write the summary only. Do not re-ask. |
| The only hook ideas are setup hooks, and there are no other candidates | Append them to the summary and skip the GitHub question, since there is nothing to file. |
| The hooks reference cannot be fetched | Do not guess event names or fields. Name the hook idea and its check, and mark the event and snippet as unchecked. |
