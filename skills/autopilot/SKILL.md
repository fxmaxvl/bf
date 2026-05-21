---
name: autopilot
description: "General autonomous wrapper — runs any bf skill without user input. Critic oracle resolves every decision. Usage: /bf:autopilot [skill] <args> (e.g. /bf:autopilot quick fix login bug)"
model: opus
disable-model-invocation: false
argument-hint: "[skill-name] <idea or args>"
allowed-tools: Read, Write, Edit, Grep, Glob, Agent, Bash(git add *), Bash(git commit *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git fetch *), Bash(git checkout *), Bash(git merge-base *), Bash(git rev-parse *), Bash(git config *), Bash(git ls-files *), Bash(git stash *), Bash(git branch *), Bash(git show *), Bash(git tag *), Bash(git reset *), Bash(gh *), Bash(bash *), mcp__*__jira__*
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Autonomous wrapper that executes any bf skill without user input. Every point where the target skill would ask the user a question, wait for approval, or stop for input is replaced by a **critic oracle** call. Everything else follows the target skill exactly.

## Step 1 — Parse arguments

`$ARGUMENTS` has the form: `[skill-name] <forwarded-args>`

Split as follows:

```
first_word=$(echo "$ARGUMENTS" | awk '{print $1}')
rest=$(echo "$ARGUMENTS" | cut -d' ' -f2-)
```

If `first_word` matches a known bf skill name (see routing table below): `target_skill=$first_word`, `target_args=$rest`.
Otherwise: `target_skill=feature`, `target_args=$ARGUMENTS` (treat the whole input as the forwarded args).

**Skill routing table:**

| Argument | SKILL.md path |
|----------|---------------|
| `feature` (default) | `${CLAUDE_PLUGIN_ROOT}/skills/bfeature/SKILL.md` |
| `quick`   | `${CLAUDE_PLUGIN_ROOT}/skills/quick/SKILL.md` |
| `micro`   | `${CLAUDE_PLUGIN_ROOT}/skills/micro/SKILL.md` |
| `review`  | `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` |
| `design`  | `${CLAUDE_PLUGIN_ROOT}/skills/design/SKILL.md` |

Read the resolved SKILL.md in full before proceeding.

Print: `── bf:autopilot | <target_skill> ───────────────────────────────`

## Step 2 — Install stop hook

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/autopilot"
bash "$SKILL_DIR/hooks/install.sh" on
```

Install also flips `permissions.defaultMode` to `"bypassPermissions"` in the project's `.claude/settings.local.json` (stashing the prior value) so cross-directory reads and non-allowlisted Bash commands run without prompts. Uninstall restores the prior value; the SessionStart and UserPromptSubmit cleanup hooks also call `install.sh off`, so the bypass mode never survives across sessions.

## Step 3 — Execute with the critic rule

Run the target skill's full workflow using `target_args` as `$ARGUMENTS`, with this single override applied everywhere:

**The critic rule:** Whenever the target skill would ask the user a question, wait for a yes/no approval, present options and wait for a choice, or stop with "re-invoke when ready" — call critic instead.

Do not stop. Do not wait. Resolve every decision via critic and continue.

## Step 4 — Calling the critic

At each decision point, read `${CLAUDE_PLUGIN_ROOT}/skills/critic/SKILL.md` and invoke it **inline** with this payload:

```
QUESTION: <the exact decision or question the target skill would have asked>
PHASE: <current phase or step name from the target skill>
SESSION_LOG: <absolute path to the session log, if the target skill maintains one — omit if not>
OPTIONS: A) <option extracted or inferred from the skill's instruction> | B) <alternative> [| C) <third if applicable>]
CONTEXT:
<tight excerpt relevant to the decision — spec section, plan block, report finding, or idea text>
```

Rules:
- Extract `OPTIONS` from the skill's instructions where given (e.g., "if yes … if no …" → A) yes / B) no). Enumerate them yourself when the skill doesn't list them explicitly.
- Omit `SESSION_LOG` if the target skill has no session log at that point.
- If critic returns confidence `low`, log the flag in the session log (or conversation) and proceed with the verdict — do not stop to ask the user. Collect all low-confidence flags and surface them in the final summary.
- If critic returns verdict B (stop/block): log the reason, uninstall the hook (`install.sh off`), and stop with a clear summary of what needs manual attention.

## Step 5 — Teardown

When the target skill reaches its normal end (cleanup, done, or a verdict-B stop), uninstall the hook:

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/autopilot"
bash "$SKILL_DIR/hooks/install.sh" off
```

Then print a compact handoff:

```
── bf:autopilot | Done ───────────────────────────────

Skill: <target_skill>
Decisions made: <N> (critic verdicts logged in session log or conversation)
Low-confidence flags: <list, or "none">
```

## Running in background

To run autopilot without blocking your main conversation, open a new Claude Code pane or terminal and invoke the skill there:

```bash
claude
/bf:autopilot feature my-idea
```

The session log at `$project_root/.bf/sessions/` is the shared artifact — readable from either pane while autopilot runs.

Note: spawning autopilot as a background Agent from within a conversation does not work — Claude Code subagents cannot spawn further subagents, which breaks the internal agent delegation that target skills (bf:feature, bf:review, etc.) depend on.

## Error recovery

If the session ends mid-run, the stop hook keeps state alive. On re-entry:
1. Run Setup (Step 2) again — reinstalls the hook and state file.
2. Read `build-state.json` (if the target skill uses one) and resume from the current phase.
3. Apply the critic rule from that point forward.

To interrupt autopilot: type anything at the prompt — the UserPromptSubmit hook wipes state immediately.
