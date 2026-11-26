---
max_turns: 30
timeout_seconds: 420
allowed_tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent]
---

/bf:micro add scripts/new-post.sh: given a post title as $1, turn the title into a URL slug (lowercase, words joined by single hyphens) and create the file posts/<slug>.md containing the title as a heading. Exit 1 with a usage line if no title is given.

(Eval harness: stop after the Execute phase. Do not run verify, review, commit, push or open a PR. Where a phase would ask a question, take the obvious default.)
