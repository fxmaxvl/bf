---
name: cross-agent
description: "Use when the user wants another coding agent (Codex, Gemini CLI, or any other) to run a bf skill, whether they name the skill or only describe its work and name the agent — 'run bf:review in codex', 'hand this bug-hunt to codex', 'let codex do the review', 'have codex review this branch', 'ask gemini to hunt for bugs in src/payments', 'dispatch the review to another agent', 'get codex's take on this PR', 'prepare a task for another agent'. Not for work Claude should do itself, and not for tasks no bf skill covers. Builds a self-contained bundle (the skill's reference closure, resolved conventions, a Claude-Code-to-other-harness translation preamble, and a brief with the context from this conversation), and with --run <agent> launches it and brings the result back."
model: sonnet
disable-model-invocation: false
argument-hint: "[--run <agent>] <skill> [skill arguments] — e.g. '--run codex bug-hunt src/payments'"
allowed-tools: Read, Write, Bash(bash *), Bash(git *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Package a bf skill for a non-Claude agent. A SKILL.md alone is not enough there: the skill reads conventions and other skills, calls scripts by `${CLAUDE_PLUGIN_ROOT}` path, and leans on Claude Code tools (Agent fan-out, AskUserQuestion, Skill). The bundle carries all of that, plus the context from this conversation that the other agent cannot see.

## On Invocation

Print banner (plain text):

```
── bf:cross-agent ──────────────────────────────────────
```

**Implicit invocation.** When the skill was triggered by intent rather than `/bf:cross-agent <args>`, build the arguments yourself before you initialize:

- **Skill:** map the intended work to the bf skill that covers it: a review → `review`, a bug sweep → `bug-hunt`, a coherence check → `coherence`, research → `research`, an architecture audit → `arch-audit`. When two skills fit, or none clearly does, ask which one (one question). Never hand off work no bf skill covers.
- **Agent:** `--run <agent>` when the request names an agent that has a runner (the `runners` list in the init output, which holds `codex` today) and asks for the work to be done. Leave it out when the request only asks to prepare something, or names an agent with no runner.
- **Skill arguments:** the scope the request names (a path, a PR number, a branch), in the target skill's own argument syntax.

State the built command in one line before you run it, e.g. *"running `/bf:cross-agent --run codex review #42`"*.

Initialize. Pass the arguments on stdin exactly like this, so quotes, spaces and `#` survive (see **Script Input** in `plugin-main.md`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/cross-agent/scripts/cross-agent-init.sh" <<'BF_ARGS'
$ARGUMENTS
BF_ARGS
```

It prints JSON: `skill`, `run`, `project_root`, `plugin_root`, `bundle_dir`, `runners`, `docs`, `scripts`. On `{"error": ...}`, see **Edge Cases & Errors**. When `$ARGUMENTS` is empty or names no skill, ask which bf skill to run and with what arguments: one question.

## Phase 1 — Brief

Write `<bundle_dir>/brief.md`. The other agent gets the skill and its conventions, so the brief carries only what this conversation knows and they do not:

- **Goal**: what the requester wants from this run, in one or two sentences, and why.
- **Scope**: files, branch, PR or area in play, if the conversation narrowed it beyond the skill arguments.
- **Context**: decisions already made, findings already known, things already ruled out, constraints the requester stated. Facts only, with file paths.
- **Authorized actions**: any outward-facing action the requester explicitly allowed (commit, push, PR comment). Write "None." when none was allowed. The preamble declines every action not listed here.

Keep it under 40 lines. Do not restate the skill's own instructions. When the conversation holds nothing beyond the arguments, write the Goal line and `Authorized actions: None.` only.

## Phase 2 — Assemble

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/cross-agent/scripts/cross-agent-assemble.sh" "<bundle_dir>"
```

It writes `<bundle_dir>/prompt.md`: the translation preamble (`references/preamble.md`), the paths, the reading list, the scripts, the brief and the verbatim arguments. It prints `prompt`, `bytes` and `run_commands`, one shell command for each runner.

## Phase 3 — Run or hand over

**Without `run`:** stop here. Report the `prompt.md` path, and say it works with any agent that takes a prompt file, run from `project_root`. List `run_commands` for the agents that have a runner.

**With `run`:** restate the effect in one line first: *"this runs bf:<skill> in <agent> on <project_root>, in a workspace-write sandbox with no network"*. Then run `run_commands.<run>` with `run_in_background: true`. These runs take minutes, and a foreground call would hit the Bash timeout. When it finishes:

- Exit 0 and `<bundle_dir>/result.md` is non-empty: read it and relay the result. Lead with the skill's findings or summary, then every `## Gate decisions` and `## Deviations` line. Do not drop the deviations: they tell the requester where this run is weaker than a Claude Code run.
- Any other outcome: report the exit code and the last 30 lines of `<bundle_dir>/run.log`. Do not retry.

## Adding a runner

A runner is `runners/<agent>.sh <bundle_dir> <project_root>`. It feeds `prompt.md` to the agent with `project_root` as the working directory, writes the agent's last message to `<bundle_dir>/result.md`, exports `CLAUDE_PLUGIN_ROOT` (the `plugin_root` from `manifest.json`), and exits with the agent's status. It exits 127 when the agent's CLI is missing. It never grants full-disk or full-network access. `runners/codex.sh` is the reference.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `unknown_skill` / `missing_skill` | Ask which bf skill to run (one question). List `ls "${CLAUDE_PLUGIN_ROOT}/skills"` if the requester asks. |
| `unknown_runner` | Say which runners exist (the error detail lists them). Offer the bundle-only path. |
| `unknown_flag` | Only `--run <agent>` may come before the skill name. Flags for the target skill go after its name. |
| `self_target` | Refuse: `cross-agent` cannot run itself. |
| `not_a_git_repo` | Stop: the runners need a repository as the working root. |
| `no_brief` from assemble | Phase 1 did not write `brief.md`. Write it, then re-run assemble. |
| Runner exits 127 | The agent's CLI is not on PATH. Report it, and give the `prompt.md` path for a manual run. |
| The skill needs `gh` or a remote (`--pr`, PR comments) | The codex sandbox has no network. Say so before the run. The requester can run the bundle by hand with network enabled (`codex exec -c sandbox_workspace_write.network_access=true ...`). |
| The skill fans out to isolated agents (bug-hunt, review gates) | The other agent does the passes one after another in one context, so they are less independent. The preamble makes it report this under Deviations. Relay it. |
