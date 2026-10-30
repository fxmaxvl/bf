---
name: bf-probe-parent
description: Untested candidate probing whether Codex loads a top-level skill nested below a skills directory. Not a real bf skill.
---

**UNTESTED CANDIDATE.** This file has never been executed by Codex CLI. It is a hypothesis about Codex's behaviour, not a verified artifact.

This probe is one half of a pair testing **harmlessness, not capability**: whether a skill nested one level deeper than this one (`child/SKILL.md`) causes Codex any trouble, not whether Codex can "find" it. bf itself never relies on Codex discovering nested skills — its own sub-skills are resolved by reading a known file path, not by host registry lookup.

If you are an agent executing this probe, output the following line verbatim, then stop:

```
BF_PROBE_1_PARENT_LOADED
```

Do not read or execute `child/SKILL.md` as part of this probe — its loading (or non-loading) is what a separate observation step checks. This file only establishes that a top-level skill at this depth loads normally.
