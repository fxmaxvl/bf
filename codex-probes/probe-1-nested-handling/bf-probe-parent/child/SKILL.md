---
name: bf-probe-child
description: Untested candidate probing whether Codex loads a skill nested below the top level of a skills directory. Not a real bf skill.
---

**UNTESTED CANDIDATE.** This file has never been executed by Codex CLI. It is a hypothesis about Codex's behaviour, not a verified artifact.

This file sits one directory deeper than `bf-probe-parent/SKILL.md` (its sibling probe). It exists to test **harmlessness, not capability** — whether Codex loading, ignoring, registering, or erroring on a nested `SKILL.md` causes any problem, since bf itself resolves its own sub-skills by file path rather than relying on host discovery of nested skills.

If you are an agent that reached this file — whether by automatic discovery or by direct invocation — output the following line verbatim, then stop:

```
BF_PROBE_1_CHILD_LOADED
```

Whether this line ever appears in a transcript, and how it got there (auto-loaded vs. directly invoked), is the observation this probe exists to produce. See the verification checklist for the full outcome matrix.
