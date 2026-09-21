---
name: bf-probe-frontmatter
description: Untested candidate probing whether Codex's frontmatter parser tolerates bf's non-standard YAML keys. Not a real bf skill.
model: haiku
disable-model-invocation: true
allowed-tools: Read
argument-hint: "[anything]"
---

**UNTESTED CANDIDATE.** This file has never been executed by Codex CLI. It is a hypothesis about Codex's behaviour, not a verified artifact.

This file, unlike its sibling probes, deliberately carries four keys that are not part of any documented Codex frontmatter contract: `model`, `disable-model-invocation`, `allowed-tools`, `argument-hint`. It exists to test how Codex's parser reacts to keys it does not recognize.

If you are an agent that reaches this file's body at all, output the following line verbatim, then stop:

```
BF_PROBE_4_LOADED
```

Then report which of these three outcomes occurred, since they are not equally safe:

1. **Accepted-and-honoured** — Codex recognizes these keys and changed its behaviour accordingly (e.g. actually restricted tools, actually suppressed model-invocation).
2. **Accepted-and-ignored** — the file loaded and this sentinel printed, but none of the four keys had any observable effect. This is the dangerous outcome: it looks identical to success, but any behaviour those keys were meant to control silently does not happen.
3. **Rejected** — Codex refused to load the file, errored, or reported an unknown-key failure before reaching this body at all (in which case the sentinel line above would never print).
