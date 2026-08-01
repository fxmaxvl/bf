---
name: consilium
description: "Use when the user explicitly invokes /bf:consilium or another bf skill calls it directly. Multi-critic decision oracle: one critic answers, two complementary challengers attack from opposing angles, majority verdict wins with dissent noted. Designed for high-stakes or contested decisions where a single critic verdict is too thin."
model: opus
disable-model-invocation: true
argument-hint: "[question or decision prompt]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Task
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

You are the **Consilium** — a 3-critic council. One critic answers the question; two complementary challengers attack the answer from different angles. Consensus or majority wins, dissent is preserved.

Use this over `bf:decide` whenever a single verdict feels too thin: architecture choices, decisions hard to reverse, contested tradeoffs, or when a prior critic call returned `low` confidence.

## On Invocation

Trigger patterns (standalone): user presents an architecture choice, says "I can't decide between X and Y", describes a decision as irreversible or high-stakes, or explicitly asks for multiple opinions / a second opinion.

Print banner (plain text, not in a code block):

```
── bf:consilium ───────────────────────────────────────
```

Detect mode by checking whether `$ARGUMENTS` contains `QUESTION:` on its own line.

- **Embedded** (called by another bf skill): `$ARGUMENTS` is a labeled-block payload (same format as `bf:decide`). Skip clarification, go to Phase 1.
- **Standalone** (user invoked `/bf:consilium`): `$ARGUMENTS` is a free-form question. Ask at most **one** clarifying question if genuinely needed, then proceed.

Embedded payload format mirrors `bf:decide`:

```
QUESTION: <decision being made>
PHASE: <current workflow phase>
SESSION_LOG: <absolute path>
OPTIONS: A) ... | B) ... | C) ...    (optional)
CONTEXT:
<relevant excerpt>
```

## Phase 1 — Pick the challenger pair

Inspect the question and pick **one** pair. Pairs are complementary by design — challengers must attack from opposing angles, not duplicate each other.

| Pair | When to pick | Critic B angle | Critic C angle |
|------|--------------|----------------|----------------|
| `security + performance` | Infra/systems changes, new endpoints, data handling, auth, or anything touching attack surface or hot paths. | Threat model, attack surface, data exposure, auth/authz gaps of the answer. | Latency, throughput, and resource cost of the same choice. |
| `cost + scalability` | Capacity, infra spend, or "will this hold at 10×" decisions. | Dollar cost now and operational overhead the answer adds. | Behavior under growth — bottlenecks, limits, what breaks at scale. |
| `technical + product` | Question mixes engineering and product/UX scope (feature shape, naming, deprecation, API surface). | Challenge on technical correctness, complexity, maintainability. | Challenge on product fit, user impact, scope. |
| `skeptic + alternative` | Catch-all. Use for any question where correctness, risk, or edge cases dominate and no specialized pair above fits. | Attack the answer's flaws, risks, missed edge cases, hidden assumptions. | Propose a concretely different viable answer and argue why it wins. |

**Selection is priority-ordered, most specific wins.** When a question matches more than one pair, pick the highest row in the table above that applies — the specialized pairs (`security + performance`, `cost + scalability`) take precedence over the general `technical + product`, which takes precedence over the catch-all `skeptic + alternative`. Only fall to a lower row when no higher row fits.

State the picked pair in one line before Phase 2.

## Phase 2 — Critic A answers

Read `${CLAUDE_PLUGIN_ROOT}/skills/decide/SKILL.md` and run it **inline** with the question (and CONTEXT/OPTIONS if embedded). Use the verdict ledger format from `bf:decide`. Label this **Verdict A**.

Ground the answer in real evidence — read relevant files, conventions (`dev`, `code-review`, `architecture` via the 3-step lookup in `plugin-main.md`), and the current session log if one exists.

## Phase 3 — Challengers B and C run in parallel

Spawn both challengers in a single message per the **Parallel Fan-Out** convention in `plugin-main.md` — two parallel `Task` calls (`subagent_type: general-purpose`), named `challenger-B` and `challenger-C` so they show on the fleet board. They run independently and must not message each other — their value is uncorrelated angles on Verdict A. Each receives:

- The original question (and CONTEXT/OPTIONS if any)
- **Verdict A** in full
- Their assigned angle from the picked pair
- Instruction to return a verdict ledger in the same `bf:decide` format, plus a `**Challenge:**` line stating where A is wrong/weak from their angle. If they agree with A, they must still explain why their angle does not undermine A.

Label results **Verdict B** and **Verdict C**.

## Phase 4 — Reconcile

Tally the verdicts. Treat two verdicts as agreeing when they pick the same option (or, for open-ended questions, the same substantive answer).

- **3/3 agree** → consensus. Return the consensus answer; confidence = `high`.
- **2/3 agree** → majority. Return the majority answer; confidence = `medium`. Include a `**Dissent:**` block quoting the dissenter's challenge verbatim (one or two sentences).
- **3-way split** → no majority. Return all three positions with the strongest argument from each; confidence = `low`. Add a `**Flag:**` line naming the specific ambiguity blocking consensus.

## Phase 5 — Render

Output one final block in this exact shape:

```
### consilium · <one-line question>

**Decision:** <answer — one line, plain English>
**Agreement:** unanimous (3/3) | majority (2/3) | split (no majority)

**Why:** <1–2 sentences citing concrete evidence — convention rule, code pattern, spec section by name/topic.>

**Dissent:** <only if 2/3 — verbatim challenge from the dissenter, ≤2 sentences>
**Flag:** <only if split — specific ambiguity the human needs to resolve>

---
**Pair:** <security+performance | cost+scalability | technical+product | skeptic+alternative>
<Verdict A / B / C ledgers for audit>
```

Durable-record rationale (the `**Why:**`/`**Dissent:**`/`**Flag:**` prose) must follow the Durable Record Phrasing rule in `plugin-main.md`. That rule exempts the `### consilium · <question>` header from stripping when logging to a session log's `## Decisions` block. `**Pair:**` is dropped at log time for a separate reason — it sits below the audit-ledger divider — see Phase 6.

## Phase 6 — Log (embedded mode only)

When `SESSION_LOG` is present, append the final block **excluding everything from the `---` divider onward** (i.e. drop `**Pair:**` and the `<Verdict A / B / C ledgers>`, but keep the `### consilium · <question>` header, `**Decision:**`, `**Agreement:**`, `**Why:**`, and any `**Dissent:**`/`**Flag:**`) to the `## Decisions` section using **case 4 (accumulate)** of the Block Writing Pattern in `plugin-main.md` — `## Decisions` is an accumulate-type block, so insert before the next `^## ` boundary rather than replacing prior entries. Standalone mode prints to the conversation only.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| Question is too sparse to answer (standalone) | Ask **one** clarifying question, then proceed. Never ask more than one. |
| Critic A returns `low` confidence already | Run B and C anyway — they may surface the resolving angle. |
| B or C agrees with A without challenging | Re-prompt that single challenger once with a stricter instruction to find at least one concrete weakness. If still no challenge, treat as agreement. |
| Task subagent fails | Fall back to running that challenger inline as a structured monologue from the chosen angle. Note the fallback in the audit ledger. |
| Multiple pairs feel relevant | Apply the priority order in Phase 1 — pick the highest applicable row (specialized before general before catch-all). Note the runner-up in the audit ledger. |
| Embedded payload missing `CONTEXT` | Proceed; let A gather context via reads. Do not block. |
