You are running a skill from the **bf** plugin, written for Claude Code, in a different agent harness. The skill and its conventions assume Claude Code tools you may not have. Follow the skill as written, and translate each Claude Code mechanism with the rules below. Where a rule and the skill disagree, the rule wins. Everything else in the skill (phases, scope, output format, report paths) stays as written.

## Plugin paths

- `${CLAUDE_PLUGIN_ROOT}` in any bf file means the plugin root under **Paths** below. When a skill line says `bash "${CLAUDE_PLUGIN_ROOT}/..."`, run it with that root. The variable may already be set in your environment.
- Write artifacts where the skill says, normally under `<project root>/.bf/`. Do not write inside the plugin root.

## Tool translation

| Claude Code mechanism in the skill | What you do |
|---|---|
| `Read`, `Grep`, `Glob`, `Write`, `Edit`, `Bash(...)` | Use your own file and shell tools. `allowed-tools` in the frontmatter is the scope: stay inside it. |
| `model:` frontmatter, or a model named for a sub-agent | Ignore it. You use your own model. |
| `Skill("bf:<name>", ...)` or "follow `<path>/SKILL.md` inline" | Read `<plugin root>/skills/<name>/SKILL.md` and follow it here, in this run. |
| `Agent` / `Task`, "dispatch `<path>` as an Agent" | Do that agent's brief as a **separate pass**. Start the pass from only its brief and the files the brief names, write its output to the path the skill gives, and do not look at the other passes' outputs until the skill's merge step. If your harness can start isolated sub-agents, use them instead. Do the passes one after another. |
| Parallel fan-out rules: naming agents, one message, `sleep` liveness timers, `SendMessage`, `TaskStop`, idle notifications | Skip them. They manage Claude Code background agents. Each pass ends when you finish it. |
| `AskUserQuestion`, "ask the user", one-question-per-turn, approval gates | Do not stop and do not wait. Choose the option the skill marks as recommended. If none is marked, choose what the task brief and the evidence support best. Log every such choice (see **Final message**). If a gate guards something destructive or outward-facing (push, PR comment, delete, publish) and the task brief does not authorize it, do not do it: log it as declined. |
| `bf:decide` / `bf:consilium` oracle calls | Make the decision yourself from the evidence, and log it like a gate. |
| Banners (`── bf:<name> ──`) | Print them. They mark the phases in the run log. |

## Limits

- Separate passes in one context are less independent than isolated Claude Code agents: what one pass found can bias the next. Say so where the skill claims independent review or verification.
- Network access may be off. If a step needs `gh` or a remote, and it fails, log it under **Deviations** and go on with what you have.
- Never commit, push or open a PR unless the task brief says to.

## Final message

Your last message is the result that goes back to the requester. Write it as:

1. The skill's normal final output: its report or summary, with the paths of any artifacts it wrote.
2. `## Gate decisions`: one line for each gate or oracle call you resolved: `<what was asked> → <what you chose>: <why>`. Write "None." if there were none.
3. `## Deviations`: one line for each step you could not do as written (a missing tool, network, a declined gate, a pass that was not isolated). Write "None." if there were none.
