---
name: autopilot
description: "Run the full bfeature workflow autonomously — critic oracle makes every decision. No user input required mid-run. Invoke with /bf:autopilot <idea>."
model: opus
disable-model-invocation: false
argument-hint: "<idea description, Jira ticket URL, or GH-ISSUE:<number>>"
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), mcp__*__jira__*
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Orchestrate the full bfeature workflow autonomously. Every gate, approval, and clarifying question is resolved by the **critic oracle** instead of user input. The phases, sub-skills, quality gates, and state machine are identical to `bf:bfeature` — this file overrides only the user-interaction points.

## Setup

Before any phase work, install the stop hook so the session survives unexpected stops between phases:

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/autopilot"
bash "$SKILL_DIR/hooks/install.sh" on
```

## Calling the Critic

At every decision point, read `${CLAUDE_PLUGIN_ROOT}/skills/critic/SKILL.md` and invoke it **inline** with this labeled-block payload:

```
QUESTION: <the decision being made>
PHASE: <current workflow phase>
SESSION_LOG: <absolute path to paths.session_log>
OPTIONS: A) <option> | B) <option> [| C) <option>]
CONTEXT:
<tight excerpt from spec, plan, or report — enough for the critic to decide>
```

- Critic logs each verdict to `## Decisions` in the session log (embedded mode).
- Omit `SESSION_LOG` only in Phase 0 before init has run — critic won't attempt a file write without it.
- Use the verdict letter (A/B/C) to determine next action. If confidence is `low`, log the flag and proceed with the verdict anyway — do not stop to ask the user.

## Sub-skill Resolution

Same as `bf:bfeature`. Read `${CLAUDE_PLUGIN_ROOT}/skills/bfeature/SKILL.md` for the full routing table, invocation patterns, artifact layout, and state update commands. Everything below overrides only gate behavior.

## Phase Flow

```
init → brainstorm [critic answers Q&A] → review-design [critic: fix?] → plan → [critic: proceed?] execute → verify → complexity-guard [critic: fix?] → review-impl [critic: fix?] → verify (silent) → [critic: finalize? todos?] finalize → collect-todos → cleanup → uninstall hook
```

---

## Phase 0 — Init

Follow `bf:bfeature` Phase 0 exactly, with one override:

**Branch selection (when `is_main` is `false`):** Call critic instead of asking the user:
```
QUESTION: Currently on <current_branch>. Continue here or create feat/<slug>?
PHASE: init
OPTIONS: A) Continue on <current_branch> | B) Create feat/<slug> from <main_branch>
CONTEXT:
Branch: <current_branch>. Main: <main_branch>. Idea: <idea>
```
*(Omit `SESSION_LOG` — init hasn't run yet. Critic prints verdict only.)*

Apply the verdict and proceed with `state-ops.sh --init`.

---

## Phase 1 — Brainstorm

Print banner. Read `${CLAUDE_PLUGIN_ROOT}/skills/bfeature/brainstorm/SKILL.md` and run the gather phase **inline**.

**Answering gather's clarifying questions:** Gather asks one question at a time. For each question, call critic instead of waiting for user input:

```
QUESTION: <gather's clarifying question verbatim>
PHASE: brainstorm
SESSION_LOG: <path>
OPTIONS: A) <most likely answer given the idea and codebase> | B) <alternative> [| C) <third if applicable>]
CONTEXT:
Idea: <idea>
<relevant codebase pattern or constraint, if any — read before calling>
```

Use the verdict as the answer, feed it back into gather's flow, and continue. After gather completes, run `brainstorm/generate` as an Agent (model: opus) per `bf:bfeature` Phase 1.

---

## Phase 2 — Review Design

Follow `bf:bfeature` Phase 2 exactly, with one override:

**Fix cycle decision:** Instead of asking "Should I fix these concerns?", call critic:
```
QUESTION: Fix the design concerns flagged in this review cycle?
PHASE: review-design
SESSION_LOG: <path>
OPTIONS: A) Yes, apply fixes | B) No, accept as-is
CONTEXT:
<concern list extracted from ## Design Report>
```

---

## Phase 3 — Plan

Follow `bf:bfeature` Phase 3 exactly, with one override:

**Execution gate:** Instead of asking "Ready to start execution?", call critic:
```
QUESTION: Plan complete. Proceed to execution?
PHASE: plan
SESSION_LOG: <path>
OPTIONS: A) Yes, proceed | B) No, stop — plan needs revision
CONTEXT:
<first 20 lines of ## Plan block>
```

If verdict is A: update state to `phase_status=in_progress`, proceed to Phase 4.
If verdict is B: log the flag from critic, uninstall the hook, and stop with a summary of what needs revision.

---

## Phase 4 — Execute

Follow `bf:bfeature` Phase 4 exactly. No user gates.

---

## Phase 4.5 — Verify

Follow `bf:bfeature` Phase 4.5 exactly. No user gates.

---

## Phase 4.75 — Complexity Guard

Follow `bf:bfeature` Phase 4.75 exactly, with one override:

**Fix cycle decision:** Instead of asking "Should I fix these complexity issues?", call critic:
```
QUESTION: Fix the blocked complexity issues?
PHASE: complexity-guard
SESSION_LOG: <path>
OPTIONS: A) Yes, apply fixes | B) No, accept as-is
CONTEXT:
<blocked issues from ## Complexity Report>
```

---

## Phase 5 — Review Implementation

Follow `bf:bfeature` Phase 5 exactly, with one override:

**Fix cycle decision:** Instead of asking "Should I fix these concerns?", call critic:
```
QUESTION: Fix the implementation concerns flagged in this review cycle?
PHASE: review-impl
SESSION_LOG: <path>
OPTIONS: A) Yes, apply fixes | B) No, accept as-is
CONTEXT:
<concern list from ## Implementation Review>
```

---

## Phase 6 — Finalize

Follow `bf:bfeature` Phase 6 exactly, with these overrides:

**Pre-finalization gate:** Instead of asking "Ready to finalize?", call critic:
```
QUESTION: All checks green. Finalize — commit, push, and open PR?
PHASE: finalize
SESSION_LOG: <path>
OPTIONS: A) Yes, finalize | B) No, stop — needs manual review
CONTEXT:
<## Plan summary, verification status: green>
```

If verdict is B: uninstall the hook, stop with a summary.

**TODO gate (full mode only):** Instead of asking "Should I scan for TODOs?", call critic:
```
QUESTION: Scan for TODO comments and collect them to the backlog?
PHASE: finalize
SESSION_LOG: <path>
OPTIONS: A) Yes, collect TODOs | B) No, skip
CONTEXT:
Idea: <idea>. Feature scope: <one-line description from spec>.
```

Set `collect_todos` in state per the verdict, then continue.

---

## Phase 7 — Collect TODOs

Follow `bf:bfeature` Phase 7 exactly.

---

## Phase 8 — Cleanup

Follow `bf:bfeature` Phase 8 exactly, then uninstall the stop hook:

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/autopilot"
bash "$SKILL_DIR/hooks/install.sh" off
```

---

## Error Recovery

Same as `bf:bfeature` — if the session ends mid-phase, the next `/bf:autopilot` invocation reads `build-state.json` and resumes. The stop hook keeps the session alive across unexpected stops. On re-entry after a stop, reinstall the hook (Setup step) before resuming the current phase.