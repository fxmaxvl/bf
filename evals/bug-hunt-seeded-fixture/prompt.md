---
max_turns: 60
timeout_seconds: 1500
allowed_tools: [Read, Write, Glob, Grep, Bash, Skill, Agent]
---

/bf:bug-hunt src

(Eval harness: run every phase through the report. Stop right after printing the report path and Findings table — do not ask the handoff question.)
