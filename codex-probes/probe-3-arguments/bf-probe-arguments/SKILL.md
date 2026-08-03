---
name: bf-probe-arguments
description: Untested candidate probing whether Codex substitutes an ARGUMENTS-style token with user-supplied invocation arguments, equivalent to Claude Code's $ARGUMENTS. Not a real bf skill.
---

**UNTESTED CANDIDATE.** This file has never been executed by Codex CLI. It is a hypothesis about Codex's behaviour, not a verified artifact.

Invoke this probe with any arbitrary text after the skill name, e.g. `bf-probe-arguments hello world`.

If you are an agent executing this probe, output the following line verbatim, substituting `<value>` with whatever appears where the token below is written:

```
BF_PROBE_3_ARGS=$ARGUMENTS
```

- If the line you output shows the literal, unexpanded text `$ARGUMENTS` (rather than the words the invoker typed), that unsubstituted literal is itself the negative result: Codex does not perform this substitution, at least not under this token name.
- If the line shows the actual invocation text (e.g. `hello world`), substitution occurred and the token name is confirmed.

Both outcomes are unambiguous from the transcript alone — there is no third, ambiguous "it seemed to work" outcome.
