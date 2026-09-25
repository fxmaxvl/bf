---
name: arch-audit
description: "Use when asked to map how an existing system is built, understand an unfamiliar codebase, or find structural bottlenecks — 'walk me through this architecture', 'how is this repo put together', 'where are the design problems'. Descends the repository layer by layer, treating each build unit as a subsystem, and produces one nested document describing every layer and the findings at it. Audits a system, not a change — for a diff, branch or PR use bf:review, and for this plugin's own skills and conventions use bf:self-audit."
model: opus
disable-model-invocation: false
argument-hint: "[free-form scope, e.g. 'deep on payments, overview elsewhere' — empty for a full descent]"
allowed-tools: Read, Write, Grep, Glob, Agent, Bash(git *), Bash(bash *), Bash(mkdir *), Bash(rtk *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Read an existing repository in concentric rounds — a whole-system overview first, then one layer
deeper each round — and produce a single nested document that describes every layer and the
structural problems found at it. Autonomous: it asks nothing once started.

## On Invocation

Verify a git repo (`git rev-parse --show-toplevel`); if there is none, stop — the repo is the
system boundary and there is nothing to descend.

Print banner (plain text):

```
── bf:arch-audit ───────────────────────────────────────
```

Resolve paths and run state in one call:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/arch-audit/scripts/run-state.sh" init "$ARGUMENTS"
```

`completed_branches` lists branches whose fragment is still on disk — those are skipped in Phase 2
and read back in Phase 3. A branch held only in context is not complete, so `init` drops any whose
fragment has gone. `prior_scope_differs: true` means this run was given a different scope than the
one the fragments were produced under; say so in the document rather than silently mixing them.

**Scope.** `$ARGUMENTS` is free-form and shapes the descent — "deep on payments, overview
elsewhere" limits full depth to the named branches and stops the rest after their own overview.
Empty means a full descent. It is never a per-round gate: the run does not stop to ask anything.

## Phase 1 — The top layer

The orchestrator reads this layer itself; subsystem boundaries are not known until it has, so
nothing can be parallelised before it.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/arch-audit/scripts/detect-units.sh" .
```

`units` are the top-level subsystems and their count is the fan-out width. `mode` says how they
were found: `build` (build/deploy units — the boundary the system is genuinely assembled from) or
`dir` (the fallback, where no build graph is discoverable).

Write the root layer section per **Layer sections** below: what this system is, what it is composed
of, what it depends on, and the findings that are visible at the whole-system level.

## Phase 2 — Branch fan-out

Spawn one agent per top-level unit, **all in a single message**, named `arch:<unit>` so the run is
legible on the fleet board. Wait for every one before continuing — the fan-out is atomic, per the
**Parallel Fan-Out** convention. Agents must not message each other.

Each agent owns its branch to the bottom and **writes its subtree as finished markdown to
`<fragments_dir>/<unit>.md`**, returning only a one-line summary. Give it: its unit path, its
fragment path, the scope text, the finding floor, and the layer-section format. Fragments are what
make a run resumable and what Phase 3 reads — a subtree that exists only in the orchestrator's
context is lost the moment the session ends.

A branch agent descends **sequentially** — subagents cannot spawn subagents, so the recursion is
recursive in structure but not in execution. Its loop, per node:

1. `detect-units.sh <path>` → write this node's layer section.
2. `has_children: false` → the branch has bottomed out. Stop.
3. Otherwise recurse into each unit, one at a time.

After each branch returns, record it — the call fails if the fragment is missing or empty, which
is the point:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/arch-audit/scripts/run-state.sh" done "<unit path>" "<fragment>"
```

## Phase 3 — Merge

Read every fragment listed in `completed_branches`. No branch agent ever saw two branches, so
anything spanning them is the orchestrator's to find:
cross-dependencies between subsystems, layer violations across boundaries, one concern solved two
different ways in two branches, and shared state reachable from more than one unit.

Then dedupe: a finding true at several layers is reported **once at the shallowest layer where it
holds**, and referenced from the deeper ones.

## Phase 4 — Write and hand off

Assemble the fragments — in the order the top layer lists their units — under the root section, and
write the result to the `doc` path from `run-state.sh paths`. Print that path, the layer and finding
counts, and the highest-severity findings.

Then offer one handoff (one question, per plugin-main.md): `/bf:feature` to act on a finding,
`/bf:adr-writer` to record a decision the audit exposed, or nothing. **This skill never edits
code** — ranking findings against each other requires that none has been acted on yet, and editing
mid-descent would invalidate the layers already described.

## Layer sections

Every layer, at every depth, emits the same three parts. Nest the headings to mirror the tree.

1. **Description** — what this layer is, what it owns, what it depends on, what depends on it,
   where its boundaries sit. This comes first and is the point: the document should teach the
   system, not just list defects.
2. **Findings** — assessed against the floor below. Each carries a **severity** and a
   **confidence**, kept separate: static inference about contention or scalability is often
   uncertain, and a document with no way to say so reads as more certain than it is.
3. **Coverage footer** — one line naming which floor concerns were assessed here. Concerns that
   found nothing are not printed as entries; without the footer, "skipped here" and "checked and
   clean" are indistinguishable, and an autonomous run has no gate where a silent drop surfaces.

### The finding floor

Every layer is assessed against all of these, with layer-specific judgment on top:

security · consistency · locking and contention · performance gaps · scalability limits ·
inconsistent behaviour · unfinished or dangling logic flows · unclear intent · layer violations ·
cross-dependencies · missing isolation around a single data-access point

All findings are **structural** — read from code and system structure. No metrics, traces or
profiles are required or used; every concern above is visible statically.

Resolve the `architecture` and `code-review` conventions via the 3-step lookup in
`plugin-main.md` and apply them when judging a layer.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Not a git repo | Stop. The repo is the system boundary; there is nothing to bound the descent. |
| `detect-units.sh` returns `mode: dir` at the root | Proceed on the directory fallback and say so in the root section — the tree is inferred, not declared. |
| A single top-level unit (no real fan-out) | Skip Phase 2's parallelism and descend inline; spawning one agent buys nothing. |
| Scope names a unit that does not exist | Note it in the root section, descend everything else fully rather than stopping. |
| A branch agent fails or writes no fragment | Leave it unrecorded, finish the others, and mark that subtree unaudited in the document. Never present a partial tree as whole. |
| Resumed run, fragments present but no document | Normal resume: descend only the missing branches, then assemble. The document is always rebuilt from fragments. |
| Resumed run under a different scope | `prior_scope_differs` is true — note in the document which branches were audited under which scope, or delete the fragments dir for a clean run. |
| Repo so large the fan-out exceeds a sane width | Descend the top layer, then process branches in batches, awaiting each batch fully before the next. |
