# bf for Codex

This directory is the Codex plugin package for bf. It is separate from the Claude Code package
at the repository root because each host has its own plugin manifest and runtime capabilities.

## Included skill

`bf-discuss` guides a one-question-at-a-time discussion, checks claims against available evidence,
and ends with a short decision record in the conversation. It does not depend on Claude Code tools,
hooks, environment variables, or model names.

## Current limits

This is the first Codex adapter, not full feature parity. The rest of bf's workflows still depend
on Claude Code-specific orchestration, tool permissions, hooks, and paths. They will be ported as
host-specific adapters while shared conventions and deterministic scripts remain reusable.

The package follows the Codex plugin layout and can be loaded as a local plugin from this
directory. See the [Codex plugin documentation](https://developers.openai.com/plugins/concepts/plugins)
for current installation and testing steps.
