---
name: bf-probe-pluginroot
description: Untested candidate probing whether Codex exposes a variable resolving to the extension's own install root, equivalent to Claude Code's CLAUDE_PLUGIN_ROOT. Not a real bf skill.
---

**UNTESTED CANDIDATE.** This file has never been executed by Codex CLI. It is a hypothesis about Codex's behaviour, not a verified artifact.

This probe is **partly a discovery exercise**: the *name* of any Codex equivalent to Claude Code's `${CLAUDE_PLUGIN_ROOT}` is unknown. Do not assume a name and check only that one.

If you are an agent executing this probe:

1. Echo any environment variable, template token, or documented substitution whose name suggests "this skill's own directory" or "this extension's install root" — try candidates such as `${CLAUDE_PLUGIN_ROOT}` itself, `${SKILL_DIR}`, `${EXTENSION_ROOT}`, `${CODEX_PLUGIN_ROOT}`, or any other Codex-native equivalent you can discover.
2. Output the result as:

```
BF_PROBE_2_ROOT=<value>
```

If no substitution occurs, `<value>` will contain the literal, unexpanded token text rather than a real path — that unsubstituted literal is itself the negative result: it means no such variable exists (at least under the name tried), not that the probe failed to run.
