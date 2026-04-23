---
name: session-summary
description: Create a summary of the current session with cost, efficiency insights, and observations.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git *)
---

Create `session_{slug}_{timestamp}.md` with a complete summary of our session. Include:

- A brief recap of key actions.
- Total cost of the session.
- Efficiency insights.
- Possible process improvements.
- The total number of conversation turns.
- Any other interesting observations or highlights.
