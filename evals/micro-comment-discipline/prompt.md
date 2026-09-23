---
max_turns: 30
timeout_seconds: 420
allowed_tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent]
---

/bf:micro add scripts/rotate-logs.sh: for the directory given as $1, gzip every *.log file older than 7 days, keep only the 5 newest .gz archives and delete older ones, and exit 1 with a usage line if the directory is missing or not given.

(Eval harness: stop after the Execute phase. Do not run verify, review, commit, push or open a PR. Where a phase would ask a question, take the obvious default.)
