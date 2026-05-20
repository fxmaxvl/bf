---
name: feature
description: Orchestrate the full brainstorm → plan → execute workflow with review gates between phases.
model: opus
disable-model-invocation: false
argument-hint: [--quick] [idea description, Jira ticket URL, or GH-ISSUE:<number>]
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), mcp__*__jira__*
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Orchestrate the full development workflow for a feature. Manage state via `.bf/sessions/build-state.json` and delegate to existing skills with approval gates between each phase.

## Artifacts Directory

All build artifacts (spec, plan, todo, backlog, build-state.json) live in `<project_root>/.bf/sessions/`. `project_root` is always the **git repository root** — resolved via `git rev-parse --show-toplevel` (NOT the current working directory, NOT a package subdirectory, NOT `~/.claude/`). The directory is created via `mkdir -p` during init and the state file is removed at the end of finalization.

## Sub-skill Resolution

Phase sub-skills (brainstorm, plan, do-todo, etc.) are **not registered** with the Skill tool and cannot be invoked via `Skill(name)`. Always locate them by reading their SKILL.md directly. Top-level skills (`bf:feature`, `bf:quick`) ARE registered and CAN be invoked via `Skill(name)` — see the handoff section.

**Reading the sub-skill's SKILL.md is mandatory before executing that phase.** Never skip this step and proceed directly to writing code or running commands. The sub-skill files contain the authoritative instructions for each phase — ignoring them causes missed quality gates, wrong outputs, and broken flows.

Sub-skill SKILL.md files are bundled with the plugin. Prepend `${CLAUDE_PLUGIN_ROOT}/skills/` to the path column in the routing table below to get the absolute path (e.g., `${CLAUDE_PLUGIN_ROOT}/skills/bfeature/brainstorm/SKILL.md`).

**Invocation patterns:**

- **Inline** (user interaction required): Read the SKILL.md at the listed path, then follow its instructions directly in the current conversation. Do **not** use the Skill tool or Agent tool. The sub-skill shares the current conversation context — state from prior steps is immediately visible to it, but user interaction is required to receive results.
- **Agent**: Read the SKILL.md at the listed path, then pass its full contents as the agent's `prompt`. Always pass the declared model. The sub-skill runs in an isolated context — it cannot see the current conversation state and must re-derive anything it needs (e.g. by re-running detect scripts). Results are returned via files, not conversation context.

## Model Routing

Each sub-skill declares a `model` field in its SKILL.md frontmatter. When delegating to a sub-skill via the Agent tool, **always pass the declared model**. The current routing:

| Sub-skill | SKILL.md path | Invocation | Model | Rationale |
|-----------|---------------|------------|-------|-----------|
| brainstorm (gather) | `full/brainstorm/SKILL.md` | Inline | — | Interactive Q&A — must stay in main conversation |
| brainstorm/generate | `full/brainstorm/generate/SKILL.md` | Agent | opus | Spec synthesis from Q&A — reasoning-heavy, no interaction needed |
| refine | `full/refine/SKILL.md` | Inline | — | Interactive Q&A — must stay in main conversation (quick mode only) |
| review-design | `full/review-design/SKILL.md` | Agent | opus | Architectural analysis — produces report, no user interaction |
| review-design/fix | `full/review-design/fix/SKILL.md` | Agent | sonnet | Applies spec fixes — execution task |
| plan | `full/plan/SKILL.md` | Agent | opus | Deep reasoning for TDD blueprints |
| do-todo | `full/do-todo/SKILL.md` | Agent | sonnet | Fast, execution-focused coding |
| verify | `full/verify/SKILL.md` | Agent | sonnet | Quality gates — runs tests (monorepo-aware) and lint with auto-fix |
| review-impl | `full/review-impl/SKILL.md` | Agent | opus | Implementation analysis — produces report, no user interaction |
| review-impl/fix | `full/review-impl/fix/SKILL.md` | Agent | sonnet | Applies code fixes — execution task |
| complexity-gate | `bfeature/complexity-gate/SKILL.md` | Agent | opus | Complexity analysis — advisory on spec and plan, blocking scan after verify |
| quality-gate | `bfeature/quality-gate/SKILL.md` | Inline | sonnet | Resolve test and lint commands; write Quality Gates section (plan phase) or output commands (verify phase) |
| collect-todos (Phase 7, optional) | `full/collect-todos/SKILL.md` | Agent | sonnet | Mechanical scanning task — skipped if user declines |

**Phase 6 (Finalize) and Phase 8 (Cleanup) are executed directly by the orchestrator** — they have no sub-skill files. The finalize logic is defined inline in this file (see Phase 6 below).

## Utility Sub-skills

Utility sub-skills are not tied to any phase. They can be invoked on-demand at any point in the workflow — typically when the user wants to explore an idea or decision before proceeding.

The discuss utility sub-skill is at `${CLAUDE_PLUGIN_ROOT}/skills/discuss/SKILL.md`.

| Sub-skill | SKILL.md path | Invocation | Model | When to use |
|-----------|---------------|------------|-------|-------------|
| discuss | `discuss/SKILL.md` | Inline | opus | Explore a question or design decision via dialogue before committing to a direction |

## Status Banners

At the start of every phase, print a banner to the conversation so the user knows where they are. Use this exact format:

```
── bfeature | Name ───────────────────────────────
```

For example: `── bfeature | Plan ───────────────────────────────`

Print the banner as plain text (not in a code block). Do this before any other work in the phase.

## Phase Flow

**Legend:**
- `[auto]` — proceeds without asking
- `[GATE]` — stops and waits for user approval
- `⇄ fix` — per-cycle "fix these concerns?" stop inside review loops

**Full mode** (default):
```
init → brainstorm → [auto] review-design ⇄ fix → [auto] plan → [GATE] execute → [auto] verify → [auto] review-impl ⇄ fix → [auto] verify (silent) → [GATE: ready + todos?] finalize (commit/push/ticket) → collect-todos? → cleanup → done
```

**Quick mode** (invoked via `/bf:feature --quick`):
```
init → refine → [auto] plan (from Q&A) → [GATE] execute → [auto] verify → [auto] review-impl ⇄ fix → [auto] verify (silent) → [GATE: ready?] finalize (commit/push/ticket) → cleanup → done
```

Quick mode skips **only** brainstorm and review-design. Every other phase — refine, plan, execute, verify, review-impl, verify (silent), finalize — is **mandatory** regardless of how simple or obvious the fix appears. Do not collapse, merge, or skip phases because the task looks trivial. The phases exist as quality gates that apply at all complexity levels.

## On Invocation

1. **Probe arguments and git state:**
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/init-probe.sh" "$ARGUMENTS"
   ```
   The script outputs JSON with:
   - `quick` — whether `--quick` was present
   - `gh_issue` — GitHub issue number or `null`
   - `jira_key` / `jira_url` — Jira ticket key and URL or `null`
   - `idea` — the clean idea text (all flags and markers stripped)
   - `current_branch`, `main_branch`, `is_main` — git branch state
   - `has_state` — whether `build-state.json` already exists
   - `project_root` — git repository root

2. If `has_state` is `true`: run `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"` to load state and resume:
   - If `phase_status` is `"awaiting_approval"`:
     - If `phase` is `"finalize"`: re-ask the pre-finalization gate per Phase 6 step 2 (one question in quick mode, two in full mode). If not ready: exit. If ready: set `phase_status` to `"in_progress"`, save `collect_todos` per Phase 6 step 2 (user's answer in full mode, `false` automatically in quick mode), update state, continue Phase 6 from step 3 (skip silent verify — it already passed).
     - Otherwise: ask "Paused before [current phase]. Ready to proceed?" — if yes, set `phase_status` to `"in_progress"`, update state, execute the current phase; if no, exit
   - Otherwise: resume the current phase from where it left off

3. If `has_state` is `false`: proceed to Phase 0 (init).

## Phase 0 — Init

Print banner: `── bfeature | Init ───────────────────────────────`

Use the `init-probe.sh` output from On Invocation (do **not** re-run it).

1. **Determine slug:**
   - If `gh_issue` is not null: set slug to `gh-<gh_issue>-<short-description>` (e.g., `gh-12-token-refresh`)
   - If `jira_key` is not null:
     - Invoke the `jira` skill to verify Jira MCP tools are available. If not available, stop.
     - Set slug to `<jira_key>-<short-description>` (e.g., `PROJ-123-dark-mode`)
     - Invoke the `jira` skill: `transition-to(jira_key, "In Progress")`
   - Otherwise: derive a short kebab-case slug from `idea` (e.g., "add dark mode" → "dark-mode")

2. **Branch selection** — use `current_branch`, `main_branch`, and `is_main` from `init-probe.sh`:
   - If `is_main` is `true`: create and checkout `feat/<slug>`
   - If `is_main` is `false`: ask the user — "You're currently on `<current_branch>`. Do you want to continue working here, or create a new branch `feat/<slug>` from `<main_branch>`?"
     - If the user chooses to continue: stay on the current branch; derive slug from branch name (strip `feat/` prefix if present)
     - If the user chooses a new branch: create and checkout `feat/<slug>` from `<main_branch>`

5. Initialize state. Build the argument list from what was detected above:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" --init \
  --slug "<slug>" \
  --idea "<idea>" \
  [--mode quick]                           # only if --quick flag was detected \
  [--jira-key PROJ-123 --jira-url <url>]   # only if Jira ticket detected \
  [--gh-issue 42]                          # only if GitHub issue detected
```

   The script creates `.bf/sessions/build-state.json`, computes `build_timestamp` in `YYYYMMDDTHH` format, and outputs JSON with `slug`, `build_timestamp`, `mode`, `paths.*`, `jira`, and `github_issue` — use these values for the rest of the session instead of re-reading state.

6. Proceed to Phase 1 (brainstorm for full mode, refine for quick mode).

**Artifact layout:** Each session produces two files (see `plugin-main.md` for the Block I/O conventions):
- `<build_timestamp>-<slug>-session-log.md` (`paths.session_log`) — persistent blocks: Spec, Plan, Todo, Backlog, Deployment
- `<build_timestamp>-<slug>-temp.md` (`paths.temp`) — ephemeral blocks: QA, Design Report, Implementation Review, Complexity Report; deleted at cleanup

Use `paths.*` from `state-ops.sh` instead of constructing paths manually.

## Phase 1 — Brainstorm (full mode only)

Print banner: `── bfeature | Brainstorm ───────────────────────────────`

Skipped entirely in quick mode — quick mode uses Phase 1Q (Refine) instead.

### Resuming from `waiting_answer`
If state has `phase` = `"brainstorm"` and `phase_status` = `"waiting_answer"`:
1. Invoke the `jira` skill: `check-for-answers(jira.ticket_key, jira.pending_questions)`
2. If all questions are answered in Jira: clear `jira.pending_questions`, set `phase_status` to `"in_progress"`, and continue the brainstorm with the new answers
3. If some questions are still unanswered in Jira: show the user the pending questions and ask — "No answer on Jira yet for these. Do you have the answers yourself, or should we keep waiting?"
   - If the user provides answers: use them, clear `jira.pending_questions`, set `phase_status` to `"in_progress"`, and continue the brainstorm
   - If the user wants to keep waiting: remain in `waiting_answer`

### If `jira.enabled` is `true`:
1. Invoke the `jira` skill: `read-ticket(jira.ticket_key)` to fetch the ticket's description, comments, and context
2. Synthesize an overall description from the ticket content
3. Read `full/brainstorm/SKILL.md` and follow its instructions **inline** (in the current conversation) with the synthesized description
   - Runs in the main conversation — user interaction is fully available
   - Gather appends the `## QA` block to `.bf/sessions/<build_timestamp>-<slug>-temp.md`
4. Read `full/brainstorm/generate/SKILL.md` and pass its contents as an Agent prompt (model: opus) to produce the spec from the Q&A

### If `jira.enabled` is `false`:
1. Read `full/brainstorm/SKILL.md` and follow its instructions **inline** (in the current conversation) with the idea from state
   - Runs in the main conversation — user interaction is fully available
   - Gather appends the `## QA` block to `.bf/sessions/<build_timestamp>-<slug>-temp.md`
2. Read `full/brainstorm/generate/SKILL.md` and pass its contents as an Agent prompt (model: opus) to produce the spec from the Q&A

### Escalating questions to Jira
If during brainstorm the user cannot answer a clarifying question and asks to post it to Jira (`jira.enabled` must be `true`):
1. Invoke the `jira` skill: `ask-author(jira.ticket_key, questions)` — this tags the ticket author and posts the questions as a comment
2. Save the questions to `jira.pending_questions` in state
3. Set `phase_status` to `"waiting_answer"`
4. Tell the user: "Questions posted to Jira ticket. Run `/bf:feature` again later to check for answers."

### In all cases:
After the generate agent completes (it appends the `## Spec` block to `paths.session_log`):
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" \
     artifacts.spec="<build_timestamp>-<slug>-session-log.md" \
     phase=review-design phase_status=in_progress
   ```
   Proceed immediately to Phase 2 (no approval gate)

## Phase 1Q — Refine (quick mode only)

Print banner: `── bfeature | Refine ───────────────────────────────`

Skipped entirely in full mode — full mode uses Phase 1 (Brainstorm) instead.

1. Read `full/refine/SKILL.md` and follow its instructions **inline** (in the current conversation) with the idea from state
   - Runs in the main conversation — user interaction is fully available
   - Appends the `## QA` block to `.bf/sessions/<build_timestamp>-<slug>-temp.md`
2. After refine completes:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=plan phase_status=in_progress
   ```
   Proceed immediately to Phase 3 (no approval gate)

## Phase 2 — Review Design (full mode only)

Print banner: `── bfeature | Review Design ───────────────────────────────`

Skipped entirely in quick mode.

Run up to 3 analyze → fix cycles:

1. Read `full/review-design/SKILL.md` and pass its contents as an Agent prompt (model: opus)
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/check-report-status.sh" "<paths.temp>" --block "## Design Report"`
3. If output is `PASS`: proceed to step 5
4. If output is `CONCERN`:
   - Show the concerns to the user
   - Ask: "Should I fix these concerns?"
   - If yes: read `full/review-design/fix/SKILL.md` and pass its contents as an Agent prompt (model: sonnet), then go back to step 1
   - If no (user accepts as-is): proceed to step 5
   - If this was already the 3rd cycle: tell the user "Max review cycles reached — please review the spec manually" and stop
5. Run complexity-gate on the spec (phase is still `review-design` — the skill auto-detects spec advisory mode):
   Read `bfeature/complexity-gate/SKILL.md` and pass its contents as an Agent prompt (model: opus).
   Show findings to the user. Always proceed regardless of outcome — findings here are advisory only.
6. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=plan phase_status=in_progress
   ```
7. Proceed immediately to Phase 3 (no approval gate)

## Phase 3 — Plan

Print banner: `── bfeature | Plan ───────────────────────────────`

1. Read `full/plan/SKILL.md` and pass its contents as an Agent prompt (model: opus) — it appends `## Plan` and `## Todo` blocks to `.bf/sessions/<build_timestamp>-<slug>-session-log.md`
2. After the plan agent completes, run complexity-gate on the plan (phase is still `plan` — the skill auto-detects plan advisory mode):
   Read `bfeature/complexity-gate/SKILL.md` and pass its contents as an Agent prompt (model: opus).
   Show findings to the user. Always proceed regardless of outcome — findings here are advisory only.
3. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" \
     artifacts.plan="<build_timestamp>-<slug>-session-log.md" \
     artifacts.todo="<build_timestamp>-<slug>-session-log.md" \
     phase=execute phase_status=awaiting_approval
   ```
   - Ask the user: "Plan written. Ready to start execution?"
   - If yes: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase_status=in_progress` — proceed to Phase 4
   - If no: **Exit** (re-invoke `/bf:feature` when ready)

## Phase 4 — Execute

Print banner: `── bfeature | Execute ───────────────────────────────`

1. Read `full/do-todo/SKILL.md` and pass its contents as an Agent prompt (model: sonnet) — it loops internally until all items are checked
2. When it completes:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=verify phase_status=in_progress
   ```
   Proceed immediately to Phase 4.5 (no approval gate)

## Phase 4.5 — Verify

Print banner: `── bfeature | Verify ───────────────────────────────`

1. Read `full/verify/SKILL.md` and pass its contents as an Agent prompt (model: sonnet)
   - Detects project type, consults conventions, determines test and lint commands
   - Runs full test suite (monorepo-scoped if applicable) — fixes failures caused by our changes; surfaces unrelated failures to the user
   - Runs linter with auto-fix where available — fixes all remaining issues manually if needed
2. When tests and lint are green:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=verify phase_status=in_progress
   ```
   Proceed immediately to Phase 4.75 (no approval gate)

## Phase 4.75 — Complexity Guard

Print banner: `── bfeature | Complexity Guard ───────────────────────────────`

Run up to 3 scan → fix cycles:

1. Read `bfeature/complexity-gate/SKILL.md` and pass its contents as an Agent prompt (model: opus)
   - Phase is `verify` — the skill auto-detects scan mode and uses `changed_files`
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/check-report-status.sh" "<paths.temp>" --block "## Complexity Report"`
3. If output is `PASS` or `ADVISORY`: show findings if any, proceed to step 5
4. If output is `BLOCK`:
   - Show the blocked issues to the user
   - Ask: "Should I fix these complexity issues?"
   - If yes: spawn a fix agent (model: sonnet) with this prompt: "Extract the `## Complexity Report` block from `paths.temp`. For each issue under Blocked Issues, apply the prescribed fix. Do not modify any file outside `changed_files`. Follow the `dev` convention (resolved via the lookup in `plugin-main.md`)."
     Then go back to step 1
   - If no (user accepts as-is): proceed to step 5
   - If this was already the 3rd cycle: tell the user "Max complexity fix cycles reached — please review the blocked issues manually" and stop
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=review-impl phase_status=in_progress
   ```
6. Proceed immediately to Phase 5 (no approval gate)

## Phase 5 — Review Implementation

Print banner: `── bfeature | Review Implementation ───────────────────────────────`

Run up to 3 analyze → fix cycles:

1. Read `full/review-impl/SKILL.md` and pass its contents as an Agent prompt (model: opus)
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/check-report-status.sh" "<paths.temp>" --block "## Implementation Review"`
3. If output is `PASS`: proceed to step 5
4. If output is `CONCERN`:
   - Show the concerns to the user
   - Ask: "Should I fix these concerns?"
   - If yes: read `full/review-impl/fix/SKILL.md` and pass its contents as an Agent prompt (model: sonnet), then go back to step 1
   - If no (user accepts as-is): proceed to step 5
   - If this was already the 3rd cycle: tell the user "Max review cycles reached — please review the implementation manually" and stop
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=finalize phase_status=in_progress
   ```
6. Proceed immediately to Phase 6 (no approval gate here — the combined gate is inside Phase 6)

## Phase 6 — Finalize

Print banner: `── bfeature | Finalize ───────────────────────────────`

1. **Silent quality gate:** Before touching git, read `full/verify/SKILL.md` and pass its contents as an Agent prompt (model: sonnet) one final time.
   - This catches any regressions introduced by review-impl fix cycles
   - If tests or lint fail: stop, tell the user which checks failed, and ask how to proceed — do **not** commit broken code
   - If all green: continue
2. **Pre-finalization gate:** Run:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase_status=awaiting_approval
   ```
   Then branch on `mode`:

   **If `mode != "quick"` (full mode):** Ask the user one question at a time:
   1. Ask: "Ready to finalize (commit, push, PR)?"
      - If no: **Exit** (re-invoke `/bf:feature` when ready).
      - If yes: continue to next question.
   2. Ask: "Should I scan for TODO comments and collect them to the backlog after?"
      - Save the answer in state as `collect_todos: true/false` so it survives session interruptions.
   Then: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase_status=in_progress collect_todos=<true|false>` — continue.

   **If `mode == "quick"` (quick mode):**
   1. Ask: "Ready to finalize (commit, push, PR)?"
      - If no: **Exit** (re-invoke `/bf:feature` when ready).
      - If yes: continue.
   Then: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase_status=in_progress collect_todos=false` — continue. (TODO scanning is always skipped in quick mode.)
3. **Compose commit message and PR content** (reasoning — model writes this):
   - **Commit message:** `feat:` prefix with a concise description. Include issue/ticket if enabled (e.g., `feat(#12): address review concerns`, `feat(PROJ-123): address review concerns`).
   - **PR title:** short, imperative (≤70 chars)
   - **PR body:** Extract the `## Spec` block from `paths.session_log` and compose a short summary (2–3 sentences max) of what the feature does and why — no test descriptions, no minor change lists, no implementation details. Store it in a variable for use in the next step.
4. **Run git finalize:**
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/finalize-git.sh" \
     --commit-msg "<commit message>" \
     --pr-title "<pr title>" \
     --pr-body "<pr body text>" \
     [--closes-issue <github_issue.number>]   # only if github_issue.enabled \
     [--jira-url <jira.ticket_url>]           # only if jira.enabled
   ```
   The script stages (excluding `.bf/sessions/`), commits if there are changes, pushes, creates the PR, and outputs the PR URL.
5. **If `jira.enabled` is `true`:**
   - Invoke the `jira` skill: `transition-to(jira.ticket_key, "To Review")`
   - Invoke the `jira` skill: `add-comment(jira.ticket_key, "PR: <pr_url>")`
6. Tell the user: "PR is up at <pr_url>. Build complete!"
7. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=collect-todos phase_status=in_progress
   ```
8. If `collect_todos` is `true` (set at the pre-finalization gate): proceed to Phase 7. Otherwise: skip Phase 7, proceed directly to Phase 8 (Cleanup)

## Phase 7 — Collect TODOs (optional)

Print banner: `── bfeature | Collect TODOs ───────────────────────────────`

1. Read `full/collect-todos/SKILL.md` and pass its contents as an Agent prompt (model: sonnet)
2. The skill scans changes introduced by the feature branch for TODO comments, classifies them, and appends a `## Backlog` block to `.bf/sessions/<build_timestamp>-<slug>-session-log.md`
3. When complete:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" artifacts.backlog="<build_timestamp>-<slug>-session-log.md"
   # or if no items found:
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" artifacts.backlog=null
   ```
4. Proceed to Phase 8 (Cleanup)

## Phase 8 — Cleanup

Print banner: `── bfeature | Cleanup ───────────────────────────────`

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/cleanup.sh"
```

Deletes ephemeral handoff files (`qa.md`, `design-report.md`, `impl-report.md`) and `build-state.json`. Persistent artifacts (`spec`, `plan`, `todo`, `backlog`, `deployment`) are kept.

## State Updates

After every phase transition, use the helper script instead of reading/writing JSON manually:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=<phase> phase_status=<status>
```

The script auto-sets `updated_at`. Use dot notation for nested fields:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" artifacts.plan=20260409T14-dark-mode-session-log.md
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" collect_todos=true
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=execute phase_status=awaiting_approval
```

Multiple key=value pairs can be passed in a single call. Boolean values (`true`/`false`) and `null` are written as JSON primitives automatically.

## Error Recovery

- If the session ends mid-phase, the next `/bf:feature` invocation reads `.bf/sessions/build-state.json` and resumes
- If the branch `feat/<slug>` already exists, switch to it instead of creating a new one
- If state shows phase `done`, tell the user the build is already complete

Here is the idea:
$ARGUMENTS
