---
name: autopilot
description: "General autonomous wrapper — runs any bf skill without user input. Oracle (decide/consilium) resolves every decision. Usage: /bf:autopilot [skill] <args> (e.g. /bf:autopilot quick fix login bug)"
model: opus
disable-model-invocation: false
argument-hint: "[skill-name] <idea or args>"
allowed-tools: Read, Write, Edit, Grep, Glob, Agent, Bash(git add *), Bash(git commit *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git fetch *), Bash(git checkout *), Bash(git merge-base *), Bash(git rev-parse *), Bash(git config *), Bash(git ls-files *), Bash(git stash *), Bash(git branch *), Bash(git show *), Bash(git tag *), Bash(git reset *), Bash(gh *), Bash(bash *), mcp__*__jira__*
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Autonomous wrapper that executes any bf skill without user input. Every point where the target skill would ask the user a question, wait for approval, or stop for input is replaced by a **decide oracle** call. Everything else follows the target skill exactly.

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
| `feature` (default) | `${CLAUDE_PLUGIN_ROOT}/skills/feature/SKILL.md` |
| `quick`   | `${CLAUDE_PLUGIN_ROOT}/skills/quick/SKILL.md` |
| `micro`   | `${CLAUDE_PLUGIN_ROOT}/skills/micro/SKILL.md` |
| `review`  | `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` |
| `design`  | `${CLAUDE_PLUGIN_ROOT}/skills/design/SKILL.md` |

Read the resolved SKILL.md in full before proceeding.

Print: `── bf:autopilot | <target_skill> ───────────────────────────────`

## Step 2 — Install stop hook

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/autopilot"
install_output=$(bash "$SKILL_DIR/hooks/install.sh" on 2>&1)
install_exit=$?
```

If `install_exit` is non-zero and `install_output` starts with `COLLISION:`:
- Extract the scope from the output (format: `COLLISION:<scope>:<state-file-path>`).
- Ask the user (one question): "bf:autopilot is already active in <scope>. Override? (yes/no)"
- If yes: run `bash "$SKILL_DIR/hooks/install.sh" on --force` and continue.
- If no: print "Autopilot aborted — existing session preserved." and stop.

Otherwise print `install_output` and continue normally.

Install maintains two scoped state files — `~/.bf/autopilot/state.json` (global) and `~/.bf/autopilot/<project-id>.json` (per-repo) — so only one autopilot can run per repo and one globally at any time. Install also flips `permissions.defaultMode` to `"bypassPermissions"` in the project's `.claude/settings.local.json` (stashing the prior value) so cross-directory reads and non-allowlisted Bash commands run without prompts. Uninstall restores the prior value; the SessionStart and UserPromptSubmit cleanup hooks also call `install.sh off`, so the bypass mode never survives across sessions.

## Step 3 — Execute with the oracle rule

Run the target skill's full workflow using `target_args` as `$ARGUMENTS`, with this single override applied everywhere:

**The oracle rule:** Whenever the target skill would ask the user a question, wait for a yes/no approval, present options and wait for a choice, or stop with "re-invoke when ready" — call an oracle (decide or consilium) instead.

**Hard rule — no phase skipping:** Never collapse, merge, or skip a phase from the target skill because the change looks small or obvious. The oracle resolves decisions; it does not override the target skill's phase structure. If a phase spawns an Agent, spawn it. If a phase runs verify, run it.

Do not stop. Do not wait. Resolve every decision via an oracle and continue.

## Step 4 — Picking the oracle

Default oracle is `decide` — fast, single verdict, cheap. **Escalate to `consilium`** (3-critic council) when ANY of these is true:

- `PHASE` is `brainstorm`, `design-review`, `spec-review`, or any phase involving architecture or open-ended ideation
- `OPTIONS` has 4 or more items (high branching — a single critic is too thin)
- `decide` was already called for this exact decision and returned `confidence: low` (re-invoke same payload via consilium to break the tie)

Both oracles accept the same labeled-block payload — only the SKILL.md path differs:

- `${CLAUDE_PLUGIN_ROOT}/skills/decide/SKILL.md` — default
- `${CLAUDE_PLUGIN_ROOT}/skills/consilium/SKILL.md` — escalation

Read the chosen oracle's SKILL.md and invoke it **inline** with this payload:

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
- If `decide` returns confidence `low`, immediately escalate: re-invoke the same payload through `consilium` and use its decision instead. Log both calls in the session log (or conversation).
- If `consilium` returns `Agreement: split (no majority)`, log the flag and proceed with the strongest single position — do not stop to ask the user. Surface the flag in the final summary.
- If the oracle returns verdict B (stop/block): log the reason, uninstall the hook (`install.sh off`), and stop with a clear summary of what needs manual attention.

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
Decisions made: <N> (oracle verdicts logged in session log or conversation; note any consilium escalations)
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
3. Apply the oracle rule from that point forward.

To interrupt autopilot: type anything at the prompt — the UserPromptSubmit hook wipes state immediately.
