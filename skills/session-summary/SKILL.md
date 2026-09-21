---
name: session-summary
description: Create a summary of the current session with efficiency insights and observations.
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

Resolve the artifact root, then write the summary to `$SESSIONS_DIR/session_{slug}_{timestamp}.md`:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT/.bf" ]; then
  SESSIONS_DIR="$PROJECT_ROOT/.bf/sessions"
else
  SESSIONS_DIR="$HOME/.bf/sessions"
fi
mkdir -p "$SESSIONS_DIR"
```

Include:

- A brief recap of key actions.
- Total cost of the session — only if the harness actually surfaces it. It usually does not, in which case write "not available" and move on. Never estimate or infer a figure.
- Efficiency insights.
- Possible process improvements.
- The total number of conversation turns, labelled as approximate unless you can count them exactly.
- Any other interesting observations or highlights.

## Step 2 — Surface skill/flow improvement candidates

After writing the file, review the session for insights that are **generalizable to the skill or workflow itself** — not specific to this session's content or cost numbers.

Ask yourself: "Would this observation apply to any user of this skill, not just this session?"

Good candidates:
- A skill step that was confusing, redundant, or missing
- A flow that could handle an edge case better
- A convention or instruction that was unclear

Not candidates:
- Session-specific details (cost, turns, what we built today)
- Observations about the user's project or code

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

The body should list each insight as a bullet point, written as a general improvement suggestion (no session-specific details). Keep each point concise and actionable.
