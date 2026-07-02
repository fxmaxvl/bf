---
name: write-skill
description: Use when asked to create a new bf skill, author a SKILL.md, build a plugin skill, add a skill to the bf plugin, or write a skill from scratch.
model: opus
disable-model-invocation: false
argument-hint: "[skill name or description, e.g. 'deploy-checker' or 'a skill that reviews Jira tickets']"
allowed-tools: Read, Write, Edit, Grep, Glob
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules, including the **one-question-per-turn** rule that applies at every interactive point in this skill.

Meta-skill for authoring a new bf-style skill. Guides you from a rough idea to a ready-to-ship `skills/<name>/SKILL.md`.

## Process

### Phase 1 — Gather

Ask ONE question at a time (per plugin-main.md). Clarify in this order, stopping as soon as the answer is evident from context:

1. **What should the skill do?** — the core capability, trigger phrase, and expected output.
2. **Does it need interactive Q&A, or is it fully autonomous?** — determines whether to include a gather/clarify phase.
3. **Does it need scripts, agents, or external tools?** — determines `allowed-tools` and whether a companion script is warranted. Scripts are the right call for any deterministic operation (path computation, JSON state, stack detection, status parsing) — they run once and pass a compact result to Claude instead of burning tokens on inline derivation.
4. **What is the target model?** — default is `sonnet`; use `opus` for multi-phase reasoning; `haiku` for cheap, fast tasks.

Stop gathering when you have enough to fill all frontmatter fields and sketch the top-level sections.

### Phase 2 — Draft

Create `skills/<name>/SKILL.md` using the template below. Fill every placeholder; delete lines that do not apply.

Start by printing the banner (plain text, not a code block):

```
── bf:write-skill ───────────────────────────────────────
```

Then write the file.

### Phase 3 — Review

Run the checklist in the **Review Checklist** section against the drafted file. Fix every gap before declaring done.

Once the checklist passes, add a row for the new skill to the `## What's inside` table in `README.md`. The table has four columns — `Skill | Kind | What it does | When to use`:

```
| `/bf:<name> <hint>` | <Workflow | Oracle | Utility> | <one-line description of what it does> | <when to reach for it> |
```

Match the concise, action-oriented style of existing rows.

---

## Skill Structure

```
skills/
  <name>/
    SKILL.md        ← required; the skill entry point
    scripts/        ← optional; shell helpers called by the skill
    hooks/          ← optional; Claude Code hook installers
```

**Single-file default.** Keep everything in `SKILL.md` unless:
- The skill exceeds ~130 lines of prose, OR
- A reusable shell script would be called from multiple skills.

Existing single-file skills for reference: `skills/review/SKILL.md`, `skills/quick/SKILL.md`, `skills/autopilot/SKILL.md`.

**Token efficiency — move work to scripts.** This plugin prizes token frugality. Before writing inline model logic, ask: can a shell script do this deterministically? If yes, write the script. The payoff compounds across every invocation:

- `state-ops.sh` — manages build-state.json and computes all artifact paths once
- `init-probe.sh` — parses arguments + git state into JSON in one bash call
- `detect-stack.sh` — identifies test/lint commands without model inference
- `check-report-status.sh` — extracts STATUS from report blocks with grep

For bash commands that produce verbose output (git log, gh queries), pipe through a token-reducing proxy (e.g. `rtk`) where available. Every token saved in a repeated command is a token available for reasoning.

---

## SKILL.md Template

````markdown
---
name: <skill-name>
description: <see Description Requirements below>
model: <opus | sonnet | haiku>
disable-model-invocation: false
argument-hint: "[free-form hint shown to user, e.g. 'idea or Jira URL']"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(gh *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

<One-line purpose statement — what this skill does and when to use it.>

## On Invocation

<Steps to run immediately on invocation: verify context, set variables, print banner.>

Print banner (plain text):

```
── bf:<name> ───────────────────────────────────────────
```

## Phase 1 — <First Phase Name>

<Instructions. Reference convention lookup from plugin-main.md if you need dev/testing/architecture/code-review conventions.>

## Phase 2 — <Second Phase Name>

<...>

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| <condition> | <how to handle> |
````

---

## Description Requirements

The `description:` field must:

- Be **third-person, action-trigger phrasing** — describe when the model should invoke the skill, not what it does internally.
- Start with "Use when…" or list trigger phrases (e.g. "Review code against…").
- Match the style of existing descriptions:
  - `review`: "Review code against feature conventions and the complexity gate."
  - `autopilot`: "General autonomous wrapper — runs any bf skill without user input."
  - `quick`: "Quick workflow (refine → plan → execute → verify → finalize) — skips brainstorm and review-design."

---

## Edge Cases

| Condition | Handling |
|-----------|----------|
| Skill name already exists under `skills/` | Warn and ask whether to overwrite or choose a different name (one question). |
| Gather phase is ambiguous after 4 questions | Draft with best-guess values; mark uncertain fields with `<!-- TODO: clarify -->`. |
| User wants scripts but skill is already >130 lines | Create `skills/<name>/scripts/` and move the script logic there; note it in the file. |

---

## Review Checklist

Before finishing, verify each item. Fix any gap before marking done.

- [ ] **Frontmatter complete** — `name`, `description`, `model`, `disable-model-invocation`, `argument-hint`, `allowed-tools` all present and filled.
- [ ] **Reads plugin-main.md first** — the exact line `Read \`${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md\` first` appears as the first non-frontmatter line.
- [ ] **ONE-question-per-turn respected** — any interactive gather phase asks one question, then waits. No batched questions anywhere in the skill.
- [ ] **Single file unless justified** — no companion files created unless the skill exceeds ~130 lines or scripts are reusable across skills.
- [ ] **README updated** — a row for the new skill is added to the `## What's inside` table in `README.md`.
- [ ] **Deterministic ops are in scripts** — path computation, JSON reads, stack detection, and status parsing are in shell scripts rather than left to the model to derive inline. Token-heavy bash output is piped through a reducing proxy (e.g. `rtk`) where available.
- [ ] **Description is action-triggered** — starts with "Use when…" or equivalent trigger phrasing; not a description of internals.
- [ ] **Convention lookup used where relevant** — if the skill needs dev/testing/architecture/code-review conventions, it uses the 3-step lookup from plugin-main.md rather than hard-coding paths.
- [ ] **Banner printed on invocation** — skill prints `── bf:<name> ──…` as plain text (not in a code block) before doing any substantive work.
- [ ] **Edge cases listed** — at least a stub `## Edge Cases & Errors` table covering the most obvious failure modes.
