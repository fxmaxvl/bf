---
name: micro
description: Micro workflow for small, focused refactors — clarifies only if needed, then executes directly with complexity and quality guards.
argument-hint: [refactoring description]
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), mcp__*__jira__*
model: opus
disable-model-invocation: false
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Orchestrate a minimal refactoring workflow. No brainstorm, no plan file, no approval gate before code. Clarify only if the instruction is ambiguous, then execute directly.

## Sub-skill Resolution

Sub-skill SKILL.md files are bundled with the plugin. Prepend `${CLAUDE_PLUGIN_ROOT}/skills/` to the path column to get the absolute path.

**Invocation patterns:**
- **Inline**: Read the SKILL.md and follow its instructions directly in the current conversation.
- **Agent**: Read the SKILL.md and pass its full contents as the agent's `prompt`. Always pass the declared model.

| Sub-skill | SKILL.md path | Invocation | Model |
|-----------|---------------|------------|-------|
| execute | `micro/execute/SKILL.md` | Agent | sonnet |
| verify | `bfeature/verify/SKILL.md` | Agent | sonnet |
| complexity-gate | `bfeature/complexity-gate/SKILL.md` | Agent | opus |
| review-impl | `bfeature/review-impl/SKILL.md` | Agent | opus |
| review-impl/fix | `bfeature/review-impl/fix/SKILL.md` | Agent | sonnet |

## Status Banners

At the start of every phase, print a banner:

```
── bfeature | Name ───────────────────────────────
```

Print as plain text (not in a code block).

## Phase Flow

```
init → [clarify if needed] → execute → verify → complexity guard → review-impl ⇄ fix → verify (silent) → [GATE: ready?] finalize → cleanup
```

## On Invocation

Check for existing state:

```bash
git rev-parse --show-toplevel
```

If `.bf/sessions/build-state.json` exists at the git root:
- Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"` to load state
- If `phase_status` is `"awaiting_approval"`: ask "Paused before [current phase]. Ready to proceed?" — if yes, set `phase_status=in_progress`, continue; if no, exit
- Otherwise: resume the current phase

If not found: start from Phase 0.

## Phase 0 — Init

Print banner: `── bfeature | Init ───────────────────────────────`

1. **Detect GitHub issue**: Check if `$ARGUMENTS` contains `GH-ISSUE:<number>`. If yes: extract the number, set `github_issue.enabled=true`, use `gh-<number>-<short-description>` as slug.
2. **Detect Jira ticket**: Check if `$ARGUMENTS` contains a Jira ticket URL. If yes: extract the ticket key, invoke the `bfeature-jira` skill to verify MCP tools are available (stop if not), transition to "In Progress", use `<ticket-key>-<short-description>` as slug.
3. If neither: derive a short kebab-case slug from the instruction (e.g., "split processOrder method" → "split-process-order").
4. **Branch selection**:
   - If on `master` (or the repo's main branch): create and checkout `feat/<slug>` from master.
   - If on a non-master branch: ask "You're on `<branch>`. Continue here or create a new branch `feat/<slug>` from master?" — act on the answer.
5. Initialize state:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" --init \
     --slug "<slug>" \
     --idea "<idea>" \
     --mode micro \
     [--jira-key PROJ-123 --jira-url <url>] \
     [--gh-issue 42]
   ```
6. Override initial phase:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=clarify phase_status=in_progress
   ```
7. Write the instruction to `paths.qa` so review-impl can use it:
   ```markdown
   # Micro Instruction

   ## Task
   <idea from $ARGUMENTS>
   ```
8. Proceed to Phase 1.

## Phase 1 — Clarify

Print banner: `── bfeature | Clarify ───────────────────────────────`

If the instruction is clear and unambiguous → proceed immediately to Phase 2. Do **not** ask anything.

If anything is ambiguous: ask ONE clarifying question (the single most important gap). Wait for the answer. If the instruction changed meaningfully, update `paths.qa` with the refined task. Then:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=execute phase_status=in_progress
```

Proceed to Phase 2.

## Phase 2 — Execute

Print banner: `── bfeature | Execute ───────────────────────────────`

Read `micro/execute/SKILL.md` and pass its contents as an Agent prompt (model: sonnet).

When it completes:
```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=verify phase_status=in_progress
```

Proceed immediately to Phase 3 (no approval gate).

## Phase 3 — Verify

Print banner: `── bfeature | Verify ───────────────────────────────`

Read `bfeature/verify/SKILL.md` and pass its contents as an Agent prompt (model: sonnet).
- Runs tests and lint, auto-fixes where possible.
- Surfaces unrelated failures to the user.

When tests and lint are green: proceed immediately to Phase 4. **Do not update `phase` — leave it as `verify`.** The complexity gate reads `phase=verify` to trigger scan mode.

## Phase 4 — Complexity Guard

Print banner: `── bfeature | Complexity Guard ───────────────────────────────`

Run up to 3 scan → fix cycles:

1. Read `bfeature/complexity-gate/SKILL.md` and pass its contents as an Agent prompt (model: opus).
   Phase is `verify` — the skill auto-detects scan mode and scans `changed_files`.
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/check-report-status.sh" "<paths.temp>" --block "## Complexity Report"`
3. If output is `PASS` or `ADVISORY`: show findings if any, proceed to step 5.
4. If output is `BLOCK`:
   - Show the blocked issues to the user.
   - Ask: "Should I fix these complexity issues?"
   - If yes: spawn a fix agent (model: sonnet) with this prompt:
     "Extract the `## Complexity Report` block from `paths.temp`. For each issue under Blocked Issues, apply the prescribed fix. Do not modify any file outside `changed_files`. Follow the `dev` convention (resolved via the lookup in `plugin-main.md`)."
     Then go back to step 1.
   - If no (user accepts as-is): proceed to step 5.
   - If this was already the 3rd cycle: tell the user "Max complexity fix cycles reached — please review the blocked issues manually" and stop.
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=review-impl phase_status=in_progress
   ```
6. Proceed immediately to Phase 5 (no approval gate).

## Phase 5 — Review Implementation

Print banner: `── bfeature | Review Implementation ───────────────────────────────`

Run up to 3 analyze → fix cycles:

1. Read `bfeature/review-impl/SKILL.md` and pass its contents as an Agent prompt (model: opus).
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/check-report-status.sh" "<paths.temp>" --block "## Implementation Review"`
3. If output is `PASS`: proceed to step 5.
4. If output is `CONCERN`:
   - Show the concerns to the user.
   - Ask: "Should I fix these concerns?"
   - If yes: read `bfeature/review-impl/fix/SKILL.md` and pass as Agent prompt (model: sonnet), then go back to step 1.
   - If no (user accepts as-is): proceed to step 5.
   - If this was already the 3rd cycle: tell the user "Max review cycles reached — please review manually" and stop.
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=finalize phase_status=in_progress
   ```
6. Proceed immediately to Phase 6 (no approval gate here — the gate is inside Phase 6).

## Phase 6 — Finalize

Print banner: `── bfeature | Finalize ───────────────────────────────`

1. **Silent quality gate**: Read `bfeature/verify/SKILL.md` and pass as Agent prompt (model: sonnet).
   - Catches regressions introduced by review-impl fix cycles.
   - If tests or lint fail: stop, tell the user which checks failed, ask how to proceed — do **not** commit broken code.
   - If green: continue.
2. **Pre-finalization gate**:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase_status=awaiting_approval
   ```
   Ask: "Ready to finalize (commit, push, PR)?"
   - If no: **Exit** (re-invoke `/bf:micro` when ready).
   - If yes: `bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase_status=in_progress` — continue.
3. Stage and commit any uncommitted changes (do **not** stage `.bf/sessions/`) following `conventions/git.md`. Use `refactor:` prefix.
   - If `github_issue.enabled`: include issue number (e.g., `refactor(#12): split processOrder into smaller methods`).
   - If `jira.enabled`: include ticket key.
4. Push the branch to remote.
5. Create a PR using `gh pr create`:
   - **PR body**: Micro mode produces no spec — extract the `## QA` block from `paths.temp` and derive a 2–3 sentence summary describing what was refactored and why.
   - If `github_issue.enabled`: append `Closes #<github_issue.number>`.
   - If `jira.enabled`: append a link to the Jira ticket.
6. If `jira.enabled`:
   - Invoke the `bfeature-jira` skill: `transition-to(jira.ticket_key, "To Review")`
   - Invoke the `bfeature-jira` skill: `add-comment(jira.ticket_key, "PR: <pr_url>")`
7. Tell the user: "PR is up at <pr_url>. Build complete!"
8. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=done phase_status=in_progress
   ```
9. Proceed to Phase 7.

## Phase 7 — Cleanup

Print banner: `── bfeature | Cleanup ───────────────────────────────`

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/cleanup.sh"
```

## State Updates

After every phase transition:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh" phase=<phase> phase_status=<status>
```

Multiple key=value pairs can be passed in a single call.

## Error Recovery

- If session ends mid-phase, the next `/bf:micro` invocation reads `build-state.json` and resumes.
- If branch `feat/<slug>` already exists, switch to it.
- If state shows phase `done`, tell the user the build is already complete.

Here is the instruction:
$ARGUMENTS
