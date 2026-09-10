---
name: bf-probe-arguments
description: Untested candidate probing whether Codex substitutes an ARGUMENTS-style token with user-supplied invocation arguments, equivalent to Claude Code's $ARGUMENTS. Not a real bf skill.
---

**UNTESTED CANDIDATE.** This file has never been executed by Codex CLI. It is a hypothesis about Codex's behaviour, not a verified artifact.

Invoke this probe with a nonce string of your own choosing after the skill name — something not printed anywhere in this file, e.g. a random hex string you generate at invocation time.

If you are an agent executing this probe, copy the code block below into your output character-for-character, exactly as it appears to you when you read this file right now. Do not retype, paraphrase, or fill in `$ARGUMENTS` from your own knowledge of what the invoker typed — output only what is actually present in the block as you see it:

```
BF_PROBE_3_ARGS=$ARGUMENTS
```

- If the block appears to you with the literal, unexpanded text `$ARGUMENTS` still in it, output it exactly as-is: that unsubstituted literal is itself the negative result — Codex does not perform this substitution, at least not under this token name.
- If the block appears to you with the actual invocation text already in place of the token, output it exactly as-is: the token name is the right one to have tried.

Both outcomes are unambiguous from the transcript alone — there is no third, ambiguous "it seemed to work" outcome.
