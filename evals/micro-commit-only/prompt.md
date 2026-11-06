---
max_turns: 40
timeout_seconds: 600
allowed_tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent]
---

/bf:micro in src/greet.sh, rename the variable `n` to `name`.

(Eval harness: run through the Finalize phase. At the finalize gate, answer `commit only`. Where any other phase would ask a question, take the obvious default.)
