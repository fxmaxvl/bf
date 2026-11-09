---
max_turns: 80
timeout_seconds: 1500
allowed_tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent]
---

/bf:quick in src/greet.sh, rename the variable `n` to `name`.

(Eval harness: run through the Finalize phase. At the finalize gate, answer `commit only`. Where any other phase would ask a question, take the obvious default.)
