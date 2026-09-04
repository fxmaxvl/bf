# feature Plugin — Shared Conventions

These rules apply to every skill in this plugin.

## User-Level Conventions

User-level conventions from `~/.claude/CLAUDE.md` and its imports are already in context — treat them as authoritative and apply them throughout skill execution.

## Engineering Guidelines

Read `guidelines.md` (resolved via the 3-step Convention Lookup below) at the start of any skill
run and apply it throughout. Unlike the action-scoped conventions in the table at the end of this
file, it is not conditional — it governs every phase of every skill.

## Interaction

- **Always ask for clarification** rather than making assumptions.
- **Ask ONE question at a time.** Never batch multiple questions into a single response. If you have several things to clarify, ask the first, wait for the answer, then ask the next. This is a hard rule, not a suggestion. **It applies at every point in every skill and sub-skill — including brainstorm, gather, refine, and any interactive phase. Mid-workflow does not exempt you from this rule.**

## Parallel Fan-Out

When a skill spawns multiple sub-agents to work the **same task from independent angles** in parallel — multi-critic councils, multi-hypothesis investigation, concurrent review gates — follow this pattern. It defines *how* to fan out; each skill still decides *whether and when* to (e.g. behind a `parallel_audit` flag, or always).

- **Name every agent.** Give each a short, descriptive name (e.g. `complexity-gate`, `consistency-gate`, `review-impl`) so the run is legible on the fleet board. No anonymous parallel `Task`/`Agent` calls.
- **Spawn together, in one message.** Issue all the parallel calls in a single message so they actually run concurrently.
- **Wait for all — the fan-out is atomic.** The orchestrator blocks until every agent returns, then synthesizes. Do not advance the workflow, or persist a mid-fan-out state, while any agent is still in flight. This keeps resume trivial: a fan-out has either not started or fully completed.
- **Keep agents independent — no peer messaging.** Fan-out agents must not `SendMessage` one another. Their worth is *uncorrelated* perspectives; cross-talk manufactures groupthink. All merging, deduping, and verdict logic happens in the orchestrator *after* every agent has returned.
- **If agents run in the background,** instruct each to report its result to the orchestrator as its final act — address it as `team-lead` (the literal `main` only resolves for agents spawned with the background flag; `team-lead` works from any teammate) — and have the orchestrator block on all completions before proceeding. A backgrounded agent that finishes its analysis but never reports will stall the fan-out.

## Convention Lookup

When you need a convention file, resolve it using this 3-step lookup — **first match wins, fully replaces the plugin default**:

1. `<project_root>/.bf/conventions/<name>.md` — use `git rev-parse --show-toplevel` to find project root
2. `~/.bf/conventions/<name>.md`
3. `${CLAUDE_PLUGIN_ROOT}/conventions/<name>.md`

## Custom Convention Discovery

Beyond the predefined convention names above, users may define arbitrarily-named convention files (e.g. `api-style.md`, `monorepo-rules.md`) in either of:

- `<project_root>/.bf/conventions/` — project-local custom conventions
- `~/.bf/conventions/` — user-global custom conventions

When working on a task where such conventions might apply, run the discovery script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/scan-conventions/scripts/discover-conventions.sh"
```

The script returns a JSON array `[{filename, tier, first_heading, path}]`. Read each file that is relevant to the current task and apply its rules alongside any predefined convention files. Project tier wins when the same filename exists in both tiers.

Alternatively, invoke `/bf:scan-conventions [task description]` — it handles discovery + relevance filtering and returns a structured list of matched files.

## ADR Awareness

Before finalizing any change that touches source code (commit/push/PR), check whether it affects an existing Architecture Decision Record.

1. Resolve the ADR directory:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/adr-writer/scripts/resolve-adr.sh"
   ```
   If `dir_exists` is `false` or `adrs` is empty, there are no ADRs to check against — skip the rest of this section silently. Do not mention ADRs at all in that case.
2. List existing ADR titles: use `adrs[].title` from step 1's output directly — do not re-derive titles with a separate scan.
3. Compare the session's changed files and decisions against those titles. Flag a match only when the change plausibly **contradicts, supersedes, or materially extends** a recorded decision — not for routine changes that merely touch the same files.
4. If one or more ADRs look affected, ask one question before proceeding with finalize:
   > This change may affect ADR `<NNNN>` — "<title>". Record a new ADR for it?
   - **Yes** → invoke `Skill("bf:adr-writer", args="<short title for the new decision>")`, then continue finalize once it returns.
   - **No** → continue finalize as normal.
5. If no ADRs are affected, skip silently — do not surface this check to the user when there's nothing to flag.

## Durable Record Phrasing

Applies wherever a verdict, rationale, or amendment rationale ends up in a durable record. Scope splits into two cases:

- **A session log's `## Decisions` block.** This is an in-session audit record. The **prose fields only** (see below) are governed by the ban. The structural scaffolding around those fields — headers like `### <PHASE> · <question>` or `### consilium · <question>`, `**Pair:**` lines, agreement tallies, and ledger dividers — is the oracle's own bookkeeping and is **permitted** to persist verbatim here, for in-session audit purposes.
- **An ADR, or any other project-facing/exported document.** Both the prose fields *and* the structural scaffolding are governed. Scaffolding must be stripped or paraphrased before anything is copied into a document of this kind — it must never appear verbatim there.

The **prose fields** (`**Why:**`, `**Dissent:**`, `**Flag:**`, and equivalent free-text rationale) must read as plain engineering rationale suitable for someone with no context on how the call was made:

- No agent, critic, or skill names (e.g. "consilium", "critic", "lenses", "bf:decide").
- No internal process mechanics (phase labels, pair names, agreement tallies, audit-ledger structure).
- No internal spec-ID references (e.g. "FR-7"). Cite what the rule or spec section *says*, by its name or topic, not its tracking ID — "the auth section of the spec," not "FR-7."

## Generated Artifacts

All generated artifacts (session logs, specs, plans, research reports, QA notes, design docs, and any other skill output) **must** be stored under a `.bf/` directory. Never use `.vs/`, `.context/`, `docs/`, or any other location for skill-generated artifacts.

Resolve the artifact root using this 2-step lookup — first match wins:

1. `<project_root>/.bf/` — use `git rev-parse --show-toplevel` to find project root
2. `~/.bf/` — fallback when there is no project root (not in a git repo)

Each skill chooses its own subdirectory under that root (e.g. `.bf/sessions/`, `.bf/research/`, `.bf/specs/`). Create the directory with `mkdir -p` before writing.

## Artifact Layout

Each session produces two files:

| File | Key | Contents | Write mode |
|------|-----|----------|------------|
| `<prefix>-session-log.md` | `paths.session_log` | Persistent blocks: Spec, Plan, Todo, Backlog, Deployment, Decisions | Spec/Plan/Todo/Backlog/Deployment: **regenerate**. Decisions: **accumulate** |
| `<prefix>-temp.md` | `paths.temp` | Ephemeral blocks: QA, Design Report, Implementation Review, Complexity Report, Consistency Report, Refine Q&A | **regenerate** |

`paths.spec`, `paths.plan`, etc. are **aliases** — they resolve to the same physical file (`session_log` or `temp`). Use `paths.block_<name>` for the matching block header (e.g. `paths.block_spec` = `## Spec`).

**Write mode** is a property of the block, not a judgment made at the call site:
- **regenerate** — the block is rewritten wholesale each time it's produced (Spec, Plan, Todo, Backlog, Deployment, QA, Design Report, Implementation Review, Complexity Report, Consistency Report, Refine Q&A, etc.).
- **accumulate** — the block is appended to over time and never overwritten (`Decisions` — every oracle call adds one more verdict).

### Block Reading Pattern

To read a specific artifact from a merged file:

1. Grep `paths.<artifact>` for `^<paths.block_<artifact>>` to find the start line
2. Grep `paths.<artifact>` for the next `^## ` after that line to find the end (use EOF if it's the last block)
3. Read `paths.<artifact>` with `offset=<start>` and `limit=<end - start>`

### Block Writing Pattern

To write an artifact block:

1. If the physical file doesn't exist: create it with `<paths.block_<artifact>>\n\n<content>`
2. If it exists but the block header is absent: append `\n\n<paths.block_<artifact>>\n\n<content>`
3. If the block header already exists and the block's write mode is **regenerate**: replace the block content in place (edit from header to next `## ` or EOF)
4. If the block header already exists and the block's write mode is **accumulate**: locate the next `^## ` after the header (or EOF) and insert the new entry immediately before that boundary — do not replace existing entries.

Do **not** overwrite the entire file — other blocks may already be present.

The available convention names and when to use each:

| Action | Convention name |
|--------|----------------|
| Writing or modifying code | `dev` |
| Writing or modifying tests | `testing` |
| Committing | `git` |
| Designing architecture | `architecture` |
| TypeScript / JavaScript work | `typescript` |
| Python work | `python` |
| Reviewing code | `code-review` |
