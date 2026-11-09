---
type: llm
weight: 2
---
PASS only if the transcript shows the run asked the finalize gate question (commit, push, PR; `yes`, `commit only` or `no`) after resuming from the saved state, instead of finalizing straight away or restarting from Phase 0. FAIL if the gate was never asked, or if the run restarted the earlier phases.
