---
name: micro
description: Micro workflow for small, focused refactors — clarifies only if needed, then executes directly with complexity and quality guards.
argument-hint: [refactoring description]
allowed-tools: Read, Write, Grep, Glob, Agent, Bash(git *), Bash(gh *), Bash(bash *), Bash(mktemp *), mcp__*__jira__*
model: opus
disable-model-invocation: false
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Orchestrate a minimal refactoring workflow. No brainstorm, no plan file, no approval gate before code. Clarify only if the instruction is ambiguous, then execute directly.

## Sub-skill Resolution

Sub-skill SKILL.md files are bundled with the plugin. Prepend `${CLAUDE_PLUGIN_ROOT}/skills/` to the path column to get the absolute path.

**Invocation patterns:** follow **Sub-skill Invocation** in `plugin-main.md`.

| Sub-skill | SKILL.md path | Invocation | Model |
|-----------|---------------|------------|-------|
| execute | `micro/execute/SKILL.md` | Agent | sonnet |
| verify | `feature/verify/SKILL.md` | Agent | sonnet |
| complexity-gate | `feature/complexity-gate/SKILL.md` | Agent | opus |
| review-impl | `feature/review-impl/SKILL.md` | Agent | opus |
| review-impl/fix | `feature/review-impl/fix/SKILL.md` | Agent | sonnet |

**Target-repo prompt.** When `## Target Repos` is non-empty, add to every verify, complexity-gate, review-impl and fix agent prompt its lines, the `## Changed Paths` lines, and: "The change lives in these checkouts, not the session repo. Run `state-ops.sh`, `read-block.sh` and report writes from the session repo. Per checkout, run `changed-packages.sh` and `detect-stack.sh` with the checkout as cwd (`cd <checkout> && bash <script>`); their `changed_files` supersede `## Changed Paths`. Run tests, lint and fixes there, use `git -C <checkout>` and absolute paths for every git command and file read or edit, and commit only there. Never edit or commit in the session repo."

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
   - **Targets in other repos** (files to change live outside the session repo): skip both bullets above — the session repo stays untouched. Per target repo, under one `mktemp -d` scratch dir: if a local checkout exists, `git -C <source> fetch origin`, then, if `git -C <source> rev-parse --verify -q origin/HEAD` fails, `git -C <source> remote set-head origin -a` (if that fails too, `remote set-head origin <name>` with `<name>` from `gh repo view <owner/repo> --json defaultBranchRef -q .defaultBranchRef.name`), then `git -C <source> worktree add <scratch>/<repo> -b feat/<slug> origin/HEAD`. If that fails because `feat/<slug>` exists: when no `git -C <source> worktree list --porcelain` entry has `branch refs/heads/feat/<slug>` and `git -C <source> rev-list feat/<slug> --not --remotes` is empty and `git -C <source> ls-remote --exit-code --heads origin feat/<slug>` finds no remote branch, `branch -D` it and retry; otherwise leave it and use the first free `feat/<slug>-<n>` (n=2, 3, ...), so no unpushed commit is lost or pulled into this PR. Without a local checkout: `gh repo clone <owner/repo> <scratch>/<repo>` and `git -C <scratch>/<repo> checkout -b feat/<slug>`. After step 5, write a `## Target Repos` block to `paths.session_log`, one line per repo: `<owner/repo> <checkout> <branch> [<source>]`. Later phases and resumes read it with `read-block.sh`.
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

**Missing targets.** When the instruction targets the same file in several repos, check it exists in each `## Target Repos` checkout. If it is missing in some, list those repos and ask one question: create the file there, skip those repos, or handle them separately in another run. On skip or separate, remove those checkouts (with a `<source>`: `worktree remove` and `branch -D` as in Phase 7; else `rm -rf <checkout>`) and drop their lines from `## Target Repos`. Ask any ambiguity question below only after this one is answered.

If the instruction is clear and unambiguous → proceed immediately to Phase 2. Do **not** ask anything.

If anything is ambiguous: ask ONE clarifying question (the single most important gap). Wait for the answer. If the instruction changed meaningfully, update `paths.qa` with the refined task. Then:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=execute phase_status=in_progress
```

Proceed to Phase 2.

## Phase 2 — Execute

Print banner: `── micro | Execute ───────────────────────────────`

Dispatch `micro/execute/SKILL.md` as an Agent (model: sonnet). If `## Target Repos` is non-empty, paste its lines into the prompt.

When it completes, if `## Target Repos` is non-empty, write a `## Changed Paths` block to `paths.session_log`: for each checkout, one line per entry of `git -C <checkout> diff --name-status origin/HEAD...HEAD`, as `<owner/repo> <status> <type> <path>`; an `R`/`C` entry prints two paths, so write `<owner/repo> <status> <type> <old> -> <new>`. `<type>` is `docs` for `.md`, `.mdx`, `.rst`, `.adoc`, else `code`; for `R`/`C`, `docs` only when both paths are. Then:
```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=verify phase_status=in_progress
```

Proceed immediately to Phase 3 (no approval gate).

## Phase 3 — Verify

Print banner: `── micro | Verify ───────────────────────────────`

Dispatch `feature/verify/SKILL.md` as an Agent (model: sonnet), with the **Target-repo prompt** when it applies (as for every gate and fix agent in Phases 4–6).
- Runs tests and lint, auto-fixes where possible.
- Surfaces unrelated failures to the user.

When tests and lint are green: proceed immediately to Phase 4. **Do not update `phase` — leave it as `verify`.** The complexity gate reads `phase=verify` to trigger scan mode.

## Phase 4 — Complexity Guard

Print banner: `── micro | Complexity Guard ───────────────────────────────`

**Non-code change check.** Both this phase and Phase 5 spawn opus agents to reason about
new code. When the task produced none, they cost two round-trips and find nothing.

Read the record first: `bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/read-block.sh" <paths.session_log> --block "## Changed Paths"`. If every line has type `docs`, skip. Otherwise run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/rename-only.sh"
```

It prints `skip: true` when every changed entry is a pure rename (`R100`) or a modification whose added and removed lines differ only inside quoted path or module literals (no whitespace, with a `/` or a dotted name), and `skip: false` for anything else. Skip this phase and Phase 5 — go straight to Phase 6 — on `skip: true`. On `skip: false`, both gates run as normal.

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
     "Read the `## Complexity Report` block with `bash \"${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/read-block.sh\" <paths.temp> --block \"## Complexity Report\"`. For each issue under Blocked Issues, apply the prescribed fix. Do not modify any file outside `changed_files`. Follow the `dev` convention (resolved via the lookup in `plugin-main.md`). Apply the rules in `<prose path>` to code comments and to all prose you return."
     Then go back to step 1.
   - If no (user accepts as-is): proceed to step 5.
   - If this was already the 3rd cycle: tell the user "Max complexity fix cycles reached. Review the blocked issues manually." and stop.
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
   - If this was already the 3rd cycle: tell the user "Max review cycles reached. Review the changes manually." and stop.
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
   **Target repos first:** if `## Target Repos` is non-empty, skip `finalize-git.sh` (in the session repo it could push to main). Instead, per line: `git -C <checkout> push -u origin <branch>`, then `gh pr create -R <owner/repo> --head <branch> --title "<pr title>" --body-file -` with the body in a quoted heredoc (`<<'PRBODY'`), never in double quotes: backticks there run as commands. If `github_issue.enabled`, end each body with `Closes <session>#<number>` when there is one target repo, else `Refs <session>#<number>` (`<session>` from `gh repo view --json nameWithOwner -q .nameWithOwner` in the session repo). GitHub closes it when that PR merges into its default branch; with several PRs, the first merge would close it early. Collect every PR URL. With several, also run `gh issue comment <number> -R <session> --body-file -` listing the URLs and saying to close the issue after the last one merges. Go to step 6.
   Otherwise run:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/finalize-git.sh" \
     --commit-msg "<commit message>" \
     --pr-title "<pr title>" \
     --pr-body "$(cat <<'PRBODY'
   <pr body text>
   PRBODY
   )" \
     --baseline <paths.untracked_baseline> \
     [--add <path>]...                        # only on a rerun after exit 3 \
     [--leave-untracked]                      # only on a rerun after exit 3 \
     [--closes-issue <github_issue.number>]   # only if github_issue.enabled \
     [--jira-url <jira.ticket_url>]           # only if jira.enabled
   ```
   The script stages tracked edits, every untracked file made since the session started (anything not in `paths.untracked_baseline`), the `--add` files and `.bf/conventions/`. It commits if there are changes, pushes, creates the PR, and outputs the PR URL.
   **Exit 3** means files that were already untracked when the session started are still untracked. The script lists them on stderr and has staged and pushed nothing. Show the list and ask which of them belong to the change (one question). Rerun with `--add` for those, plus `--leave-untracked` when any remain. Under `/bf:autopilot`, rerun with `--leave-untracked`: a file that was there before the session never goes into the commit unasked.
   **Exit 1** with a git error means an `--add` path is missing, ignored, or outside the repo. Nothing was staged. Drop that path and rerun.
6. If `jira.enabled`:
   - Invoke the `jira` skill: `transition-to(jira.ticket_key, "To Review")`
   - Invoke the `jira` skill: `add-comment(jira.ticket_key, "PR: <pr_url>")`
7. Tell the user: "PR is up at <pr_url>. Build complete!" For target repos, list one PR URL per repo. When a rerun used `--leave-untracked`, add one line naming the files left out of the commit.
8. ```
   bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh" phase=done phase_status=in_progress
   ```
9. Proceed to Phase 7.

## Phase 7 — Cleanup

Print banner: `── micro | Cleanup ───────────────────────────────`

For each `## Target Repos` line with a `<source>`, first run `git -C <source> worktree remove <checkout>`. If it refuses (modified or untracked files), show `git -C <checkout> status --short` and ask one question: discard them (rerun with `--force`) or keep the checkout. Once removed, `git -C <source> branch -D <branch>` (the pushed PR branch keeps the commits). When no checkout was kept, `rm -rf <scratch>` (the parent dir of the checkouts; this also removes the clones); otherwise tell the user the kept paths. Then:

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
- If branch `feat/<slug>` already exists in the session repo, switch to it. In a target repo, Phase 0 handles it.
- If state shows phase `done`, tell the user the build is already complete.

Here is the instruction:
$ARGUMENTS
