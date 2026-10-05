---
max_turns: 120
timeout_seconds: 1800
allowed_tools: [Read, Write, Edit, Glob, Grep, Bash, Skill, Agent, WebSearch, WebFetch]
---

/bf:onboard-project backend dev, will own the cart

(Eval harness: write the course under `./.eval-home` instead of the real home. Prefix every probe call with `HOME="$PWD/.eval-home"` and use the workspace path the probe returns. Use the slug `eval-fixture` (`init eval-fixture`). Where a phase would ask a question, answer `none`; do not offer to open the course map. Stop after the Phase 6 summary.)
