---
name: session-summary
description: Create a summary of the current session with efficiency insights and observations, and check where a hook could have caught a problem.
model: sonnet
disable-model-invocation: true
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(mkdir *), Bash(gh issue create *)
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

Not candidates:
- Session-specific details (cost, what we built today)
- Observations about the user's project or code

### Hook lens

An instruction the model must remember fails in long sessions. A hook runs every time. So for each problem the session hit, ask: "Could a hook have caught or prevented this, without the model remembering?" Look for:

- A correction the user or a reviewer made more than once
- A rule in a skill or convention that the model forgot
- A manual step repeated by hand, such as a reinstall or a re-check
- A wasted turn, such as a forced continuation or a duplicate notification

Propose a hook only when its check is mechanical: a path, a command pattern, a field in the hook input, a lint result. A judgment call stays in the skill text. For each candidate, name the event (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `SessionStart`), the matcher, what it checks, and whether it blocks or only advises. Prefer advice. A hook should block only when a miss is worse than a false block. The event and input reference is https://code.claude.com/docs/en/hooks.

Sort each candidate:

- **bf could ship it**: it helps any bf user, for example a check on a bf script or a bf workflow step. It joins the Step 3 candidates with a `hook:` prefix.
- **Setup-specific**: it fits only this user's tools, commands or repos. Append it to the summary file under a `## Hooks for your setup` section, with a `settings.json` snippet. List it only, never install it, and never put it in the GitHub issue.

A hook that the session already ran, from bf or from the user's settings, is not a candidate. If it fired and still missed the problem, suggest a fix to that hook instead.

## Step 3 — Propose a GitHub issue

If you found any candidates, present them all as a bulleted list and ask:

> "Want me to file these as a single GitHub issue on `fxmaxvl/bf`? (yes/no)"

If the user says yes, create one consolidated issue:

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
| Neither `<project_root>/.bf/` nor `~/.bf/` is writable | Print the summary to the conversation and say it could not be persisted. Never drop it silently. |
| Not in a git repository | Use the `~/.bf/sessions` fallback; the summary does not need a repo. |
| In a git repo, but `.bf/sessions` is not git-ignored | Use the `~/.bf/sessions` fallback, so the summary does not show up in the repo. |
| The session has nothing worth summarizing | Say so in one line and write nothing rather than padding a file. |
| `gh issue create` fails or `gh` is unauthenticated | Keep the written summary, report the failure, and print the issue body so the user can file it by hand. |
| The user declines the improvement issue | Write the summary only. Do not re-ask. |
| The only candidates are setup-specific hooks | Append them to the summary and skip the GitHub question, since there is nothing to file. |
