---
name: micro
description: Micro workflow for small, focused refactors — clarifies only if needed, then executes directly with complexity and quality guards.
argument-hint: [refactoring description]
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), Bash(bash *), mcp__*__jira__*
model: opus
disable-model-invocation: false
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Orchestrate a minimal refactoring workflow. No brainstorm, no plan file, no approval gate before code. Clarify only if the instruction is ambiguous, then execute directly.

## Sub-skill Resolution

Sub-skill SKILL.md files are bundled with the plugin. Prepend `${CLAUDE_PLUGIN_ROOT}/skills/` to the path column to get the absolute path.

**Invocation patterns:**
- **Inline**: Read the SKILL.md and follow its instructions directly in the current conversation.
- **Agent** (written below as "dispatch `<path>` as an Agent"): do **not** read the SKILL.md yourself. Interpolate its resolved absolute path into the agent's `prompt` and instruct the agent to read that file and follow it — `${CLAUDE_PLUGIN_ROOT}` is expanded by the orchestrator because the agent cannot expand it. Any per-phase overrides go in the prompt alongside the path. Always pass the declared model.

| Sub-skill | SKILL.md path | Invocation | Model |
|-----------|---------------|------------|-------|
| execute | `micro/execute/SKILL.md` | Agent | sonnet |
| verify | `feature/verify/SKILL.md` | Agent | sonnet |
| complexity-gate | `feature/complexity-gate/SKILL.md` | Agent | opus |
| review-impl | `feature/review-impl/SKILL.md` | Agent | opus |
| review-impl/fix | `feature/review-impl/fix/SKILL.md` | Agent | sonnet |

## Status Banners

At the start of every phase, print a banner:

```
── micro | Name ───────────────────────────────
```

Print as plain text (not in a code block).

## Phase Flow

```
init → [clarify if needed] → execute → verify → [complexity guard → review-impl ⇄ fix, skipped for non-code changes] → verify (silent) → [GATE: ready?] finalize → cleanup
```

## On Invocation

Check for existing state:

```bash
git rev-parse --show-toplevel
```

If `.bf/sessions/build-state.json` exists at the git root:
- Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"` to load state
- If `phase_status` is `"awaiting_approval"`: ask "Paused before [current phase]. Ready to proceed?" — if yes, set `phase_status=in_progress`, continue; if no, exit
- Otherwise: resume the current phase

If not found: start from Phase 0.

## Phase 0 — Init

Print banner: `── micro | Init ───────────────────────────────`

1. **Detect GitHub issue**: Check if `$ARGUMENTS` contains `GH-ISSUE:<number>`. If yes: extract the number, set `github_issue.enabled=true`, use `gh-<number>-<short-description>` as slug.
2. **Detect Jira ticket**: Check if `$ARGUMENTS` contains a Jira ticket URL. If yes: extract the ticket key, invoke the `jira` skill to verify MCP tools are available (stop if not), transition to "In Progress", use `<ticket-key>-<short-description>` as slug.
3. If neither: derive a short kebab-case slug from the instruction (e.g., "split processOrder method" → "split-process-order").
4. **Branch selection**:
   - If on `master` (or the repo's main branch): create and checkout `feat/<slug>` from master.
   - If on a non-master branch: ask "You're on `<branch>`. Continue here or create a new branch `feat/<slug>` from master?" — act on the answer.
5. Initialize state:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" --init \
     --slug "<slug>" \
     --idea "<idea>" \
     --mode micro \
     [--jira-key PROJ-123 --jira-url <url>] \
     [--gh-issue 42]
   ```
6. Override initial phase:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=clarify phase_status=in_progress
   ```
7. Write the instruction to `paths.qa` under the `## QA` block header — that is the header
   review-impl, its fix pass, and the Phase 6 PR body all read:
   ```markdown
   # Micro Instruction

   ## QA
   <idea from $ARGUMENTS>
   ```
8. Proceed to Phase 1.

## Phase 1 — Clarify

Print banner: `── micro | Clarify ───────────────────────────────`

If the instruction is clear and unambiguous → proceed immediately to Phase 2. Do **not** ask anything.

If anything is ambiguous: ask ONE clarifying question (the single most important gap). Wait for the answer. If the instruction changed meaningfully, update `paths.qa` with the refined task. Then:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=execute phase_status=in_progress
```

Proceed to Phase 2.

## Phase 2 — Execute

Print banner: `── micro | Execute ───────────────────────────────`

Dispatch `micro/execute/SKILL.md` as an Agent (model: sonnet).

When it completes:
```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=verify phase_status=in_progress
```

Proceed immediately to Phase 3 (no approval gate).

## Phase 3 — Verify

Print banner: `── micro | Verify ───────────────────────────────`

Dispatch `feature/verify/SKILL.md` as an Agent (model: sonnet).
- Runs tests and lint, auto-fixes where possible.
- Surfaces unrelated failures to the user.

When tests and lint are green: proceed immediately to Phase 4. **Do not update `phase` — leave it as `verify`.** The complexity gate reads `phase=verify` to trigger scan mode.

## Phase 4 — Complexity Guard

Print banner: `── micro | Complexity Guard ───────────────────────────────`

**Non-code change check.** Both this phase and Phase 5 spawn opus agents to reason about
new code. When the task produced none, they cost two round-trips and find nothing:

```bash
git diff --name-status origin/HEAD...HEAD
```

Diff against the remote-tracking ref, not a local branch name — a local `main` that is behind
its remote reports renames as unpaired adds, which reads as new code and silently forfeits the
skip. Skip this phase and Phase 5 — go straight to Phase 6 — when every changed entry is either a pure
rename (`R100`) or a modification whose added and removed lines differ only in a path or
module string. `R100` is load-bearing: a rename that also carries edits scores below it
(`R099` and down), so it fails this test on its own. Anything else, including a single new
conditional or dependency, means both gates run as normal. When the diff is mixed or unclear, run them: a
gate skipped over real code costs more than two spent round-trips.

If skipping, record it and say so:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=finalize phase_status=in_progress
```

Tell the user which gates were skipped and which check licensed it, then proceed to Phase 6.

Otherwise, run up to 3 scan → fix cycles:

1. Dispatch `feature/complexity-gate/SKILL.md` as an Agent (model: opus).
   Phase is `verify` — the skill auto-detects scan mode and scans `changed_files`.
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "<paths.temp>" --block "## Complexity Report"`
3. If output is `PASS` or `ADVISORY`: show findings if any, proceed to step 5.
4. If output is `BLOCK`:
   - Show the blocked issues to the user.
   - Ask: "Should I fix these complexity issues?"
   - If yes: spawn a fix agent (model: sonnet) with this prompt:
     "Read the `## Complexity Report` block with `bash \"${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/read-block.sh\" <paths.temp> --block \"## Complexity Report\"`. For each issue under Blocked Issues, apply the prescribed fix. Do not modify any file outside `changed_files`. Follow the `dev` convention (resolved via the lookup in `plugin-main.md`)."
     Then go back to step 1.
   - If no (user accepts as-is): proceed to step 5.
   - If this was already the 3rd cycle: tell the user "Max complexity fix cycles reached — please review the blocked issues manually" and stop.
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=review-impl phase_status=in_progress
   ```
6. Proceed immediately to Phase 5 (no approval gate).

## Phase 5 — Review Implementation

Print banner: `── micro | Review Implementation ───────────────────────────────`

Run up to 3 analyze → fix cycles:

1. Dispatch `feature/review-impl/SKILL.md` as an Agent (model: opus).
2. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/check-report-status.sh" "<paths.temp>" --block "## Implementation Review"`
3. If output is `PASS`: proceed to step 5.
4. If output is `CONCERN`:
   - Show the concerns to the user.
   - Ask: "Should I fix these concerns?"
   - If yes: dispatch `feature/review-impl/fix/SKILL.md` as an Agent (model: sonnet), then go back to step 1.
   - If no (user accepts as-is): proceed to step 5.
   - If this was already the 3rd cycle: tell the user "Max review cycles reached — please review manually" and stop.
5. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=finalize phase_status=in_progress
   ```
6. Proceed immediately to Phase 6 (no approval gate here — the gate is inside Phase 6).

## Phase 6 — Finalize

Print banner: `── micro | Finalize ───────────────────────────────`

1. **Silent quality gate**: dispatch `feature/verify/SKILL.md` as an Agent (model: sonnet).
   - Catches regressions introduced by review-impl fix cycles.
   - If tests or lint fail: stop, tell the user which checks failed, ask how to proceed — do **not** commit broken code.
   - If green: continue.
2. **Pre-finalization gate**:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase_status=awaiting_approval
   ```
   Ask: "Ready to finalize (commit, push, PR)?"
   - If no: **Exit** (re-invoke `/bf:micro` when ready).
   - If yes: `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase_status=in_progress` — continue.
3. **ADR check:** apply the **ADR Awareness** convention from `plugin-main.md` against this session's changed files/decisions. Resolve and act on it before committing.
4. **Compose commit message and PR content** (reasoning — model writes this), following the `git` convention (resolved via the lookup in `plugin-main.md`):
   - **Commit message**: `refactor:` prefix with a concise description. If `github_issue.enabled`, include the issue number (e.g., `refactor(#12): split processOrder into smaller methods`); if `jira.enabled`, include the ticket key.
   - **PR title**: short, imperative (≤70 chars).
   - **PR body**: Micro mode produces no spec — read the `## QA` block with `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/read-block.sh" <paths.temp> --block "## QA"` and derive a 2–3 sentence summary describing what was refactored and why.
   - **Coverage note**: when the change adds logic with more than one outcome, name which branches were actually executed during verify and which were only reasoned about. Cheap-to-drive paths and paths needing conditions that do not exist in the repo right now are not the same claim, and the undriven one is where the first real-use defect lands. A body that says "verified" without that split overstates coverage. Omit the note entirely when the change has no branching behaviour of its own.
5. **Run git finalize:**
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/finalize-git.sh" \
     --commit-msg "<commit message>" \
     --pr-title "<pr title>" \
     --pr-body "<pr body text>" \
     [--closes-issue <github_issue.number>]   # only if github_issue.enabled \
     [--jira-url <jira.ticket_url>]           # only if jira.enabled
   ```
   The script stages (excluding `.bf/sessions/`), commits if there are changes, pushes, creates the PR, and outputs the PR URL.
6. If `jira.enabled`:
   - Invoke the `jira` skill: `transition-to(jira.ticket_key, "To Review")`
   - Invoke the `jira` skill: `add-comment(jira.ticket_key, "PR: <pr_url>")`
7. Tell the user: "PR is up at <pr_url>. Build complete!"
8. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=done phase_status=in_progress
   ```
9. Proceed to Phase 7.

## Phase 7 — Cleanup

Print banner: `── micro | Cleanup ───────────────────────────────`

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/cleanup.sh"
```

## State Updates

After every phase transition:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=<phase> phase_status=<status>
```

Multiple key=value pairs can be passed in a single call.

## Error Recovery

- If session ends mid-phase, the next `/bf:micro` invocation reads `build-state.json` and resumes.
- If branch `feat/<slug>` already exists, switch to it.
- If state shows phase `done`, tell the user the build is already complete.

Here is the instruction:
$ARGUMENTS
