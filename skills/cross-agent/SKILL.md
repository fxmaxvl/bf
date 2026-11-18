---
name: cross-agent
description: "Use when the user wants another coding agent (Codex, Gemini CLI, or any other) to run a bf skill, whether they name the skill or only describe its work and name the agent — 'run bf:review in codex', 'hand this bug-hunt to codex', 'let codex do the review', 'have codex review this branch', 'ask gemini to hunt for bugs in src/payments', 'dispatch the review to another agent', 'get codex's take on this PR', 'prepare a task for another agent'. Not for work Claude should do itself, and not for tasks no bf skill covers. Builds a self-contained bundle (the skill's reference closure, resolved conventions, a Claude-Code-to-other-harness translation preamble, and a brief with the context from this conversation), and with --run <agent> launches it and brings the result back."
model: sonnet
disable-model-invocation: false
argument-hint: "[--run <agent>] [--read-only] <skill> [skill arguments] — e.g. '--run codex bug-hunt src/payments'"
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

- **Skill:** map the intended work to the bf skill that covers it: a review → `review`, a bug sweep → `bug-hunt`, a coherence check → `coherence`, research → `research`, an architecture audit → `arch-audit`. A single audit gate is a sub-skill: `feature/consistency-gate` or `feature/complexity-gate`. When two skills fit, or none clearly does, ask which one (one question). Never hand off work no bf skill covers.
- **Agent:** `--run <agent>` when the request names an agent that has a runner (the `runners` list in the init output, which holds `codex` today) and asks for the work to be done. Leave it out when the request only asks to prepare something, or names an agent with no runner.
- **Sandbox:** `--read-only` when the target only reports and writes nothing (`feature/consistency-gate`, `feature/complexity-gate`), or when the request asks for a read-only run. Leave it out otherwise: most skills write their `.bf/` artifacts.
- **Skill arguments:** the scope the request names (a path, a PR number, a branch), in the target skill's own argument syntax.

State the built command in one line before you run it, e.g. *"running `/bf:cross-agent --run codex review #42`"*.

Initialize. Write `$ARGUMENTS` exactly as given, or the arguments you built, with the Write tool, to `<working directory>/.bf/tmp/cross-agent-args.txt` (an empty file when there are no arguments). Then run the script with that file on stdin. Never put the arguments in a heredoc: a line in them that matches the terminator ends it, and the lines after it run as commands.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/cross-agent/scripts/cross-agent-init.sh" < "<working directory>/.bf/tmp/cross-agent-args.txt"
```

It prints JSON: `skill`, `run`, `sandbox`, `project_root`, `plugin_root`, `bundle_dir`, `runners`, `docs`, `scripts`. On `{"error": ...}`, see **Edge Cases & Errors**. When `$ARGUMENTS` is empty or names no skill, ask which bf skill to run and with what arguments: one question.

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

It writes `<bundle_dir>/prompt.md`: the translation preamble (`references/preamble.md`), the paths, a reading list (the conventions and the skill's own SKILL.md and `references/` to read first, and every other doc the skill cites to read when the skill sends the agent there), the scripts, the brief and the verbatim arguments. It prints `prompt`, `bytes` and `run_commands`, one shell command for each runner.

## Phase 3 — Run or hand over

**Without `run`:** stop here. Report the `prompt.md` path, and say it works with any agent that takes a prompt file, run from `project_root`. List `run_commands` for the agents that have a runner.

**With `run`:** restate the effect in one line first: *"this runs bf:<skill> in <agent> on <project_root>, in a <sandbox> sandbox with no network"*. Then run `run_commands.<run>` with `run_in_background: true`. These runs take minutes, and a foreground call would hit the Bash timeout. When it finishes:

- Exit 0 and `<bundle_dir>/result.md` is non-empty: read it and relay the result. Lead with the skill's findings or summary, then every `## Gate decisions` and `## Deviations` line. Do not drop the deviations: they tell the requester where this run is weaker than a Claude Code run.
- A gate run for a flow: the caller writes the block, not the gate. Under `--read-only` the gate's own `write-block.sh` call fails, and its report still comes back as its last message. Put the gate's target in the brief the way bf:review's gate prompts do (an `OVERRIDE — changed_files` list), so the gate does not depend on a session it cannot see. Then take the lines of `result.md` after its `## <Name> Report` line, up to the next `## ` line, and write them with `write-block.sh <paths.<gate>_report> --block "<paths.block_<gate>_report>"`, as the Block Writing Pattern in `plugin-main.md` describes. Relay the `## Deviations` that follow as usual.
- Any other outcome: report the exit code and the last 30 lines of `<bundle_dir>/run.log`. When `run.log` does not exist, the runner stopped before the agent started (exit 2 or 127). Its reason is on stderr, in the background task's output: report that instead. Do not retry.

## Adding a runner

A runner is `runners/<agent>.sh <bundle_dir> <project_root>`. It feeds `prompt.md` to the agent with `project_root` as the working directory, writes the agent's last message to `<bundle_dir>/result.md`, exports `CLAUDE_PLUGIN_ROOT` (the `plugin_root` from `manifest.json`), runs the agent in the manifest's `sandbox` (`read-only` or `workspace-write`, exit 2 on any other value), and exits with the agent's status. It exits 127 when the agent's CLI is missing. It never grants full-disk or full-network access. `runners/codex.sh` is the reference.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `unknown_skill` / `missing_skill` | Ask which bf skill to run (one question). The `unknown_skill` detail lists the top-level skills that can run. Offer those. A sub-skill runs as `<skill>/<sub-skill>`, e.g. `feature/consistency-gate`. |
| `unknown_runner` | Say which runners exist (the error detail lists them). Offer the bundle-only path. |
| `unknown_flag` | Only `--run <agent>` and `--read-only` may come before the skill name. Flags for the target skill go after its name. |
| `self_target` | Refuse: `cross-agent` cannot run itself, or one of its own sub-paths. |
| A skill under `--read-only` needs to write (its `.bf/` artifacts, a fix) | The sandbox refuses the write and the run reports it under Deviations. Relay it, and offer a rerun without `--read-only`. |
| `not_a_git_repo` | Stop: the runners need a repository as the working root. |
| `no_brief` from assemble | Phase 1 did not write `brief.md`. Write it, then re-run assemble. |
| `no_manifest`, `bad_manifest`, `no_args` or `usage` from assemble | The bundle is incomplete or was not made by init. Start over from **On Invocation**: init makes a fresh bundle dir. |
| `no_jq` | Stop: both scripts need `jq`. Say so, and that installing it fixes the run. |
| `conventions_failed`, `manifest_failed`, `mkdir_failed` or `write_failed` | Stop and report the detail. These are environment failures (an unreadable plugin, a read-only `.bf/`), and a rerun does not fix them. |
| Any other `{"error": ...}` | Stop and report the code and the detail as given. |
| Runner exits 127 | The agent's CLI is not on PATH. Report it, and give the `prompt.md` path for a manual run. |
| Runner exits 2 | The runner refused the bundle before the agent started: wrong arguments, no `prompt.md`, or a manifest with no `plugin_root`. There is no `run.log`. Report the stderr line from the background task output. |
| The skill needs `gh` or a remote (`--pr`, PR comments) | The codex sandbox has no network. Say so before the run. The requester can run the bundle by hand with network enabled (`codex exec -c sandbox_workspace_write.network_access=true ...`). |
| The skill fans out to isolated agents (bug-hunt, review gates) | The other agent does the passes one after another in one context, so they are less independent. The preamble makes it report this under Deviations. Relay it. |
