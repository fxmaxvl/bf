---
name: write-skill
description: Use when asked to create a new bf skill, author a SKILL.md, build a plugin skill, add a skill to the bf plugin, or write a skill from scratch.
model: opus
disable-model-invocation: false
argument-hint: "[skill name or description, e.g. 'deploy-checker' or 'a skill that reviews Jira tickets']"
allowed-tools: Read, Write, Edit, Grep, Glob
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules, including the **one-question-per-turn** rule that applies at every interactive point in this skill.

Meta-skill for authoring a new bf skill. Creates a portable Agent Skill by default at
`skills/<name>/SKILL.md`; keep host-specific runtime behavior out of the portable skill.

## Process

### Phase 1 — Gather

Ask ONE question at a time (per plugin-main.md). Clarify in this order, stopping as soon as the answer is evident from context:

1. **What should the skill do?** — the core capability, trigger phrase, and expected output.
2. **Does it need interactive Q&A, or is it fully autonomous?** — determines whether to include a gather/clarify phase.
3. **Does it need scripts, agents, or external tools?** — determine which capabilities are required and whether they exist across the target agents. Put deterministic work in a script. Do not assume another host has Claude's `Agent`, `Skill`, hooks, or tool-permission model.
4. **Does it require a specific host?** — default to a portable Agent Skill. Ask for a host only when the requested behavior depends on a host-specific API, hook, tool, or invocation feature.

Stop gathering when you have enough to write the two required Agent Skills fields and sketch the top-level sections.

### Phase 2 — Draft

Create `skills/<name>/SKILL.md` using the portable template below. Fill every placeholder; delete lines that do not apply. If the user explicitly requests Claude Code-specific behavior, preserve the required Claude metadata and label the skill Claude Code-only in its description and the README.

Then write the file.

### Phase 3 — Review

Run the checklist in the **Review Checklist** section against the drafted file. Fix every gap before declaring done.

Once the checklist passes, add a row for the new skill to the `## What's inside` table in `README.md`. The table has four columns — `Skill | Kind | What it does | When to use`:

For a portable skill, identify it as `bf-<name> (portable)` in the first column. For a Claude-only
skill, use its `/bf:<name>` command. Do not imply that every host uses Claude's slash-command syntax.

Match the concise, action-oriented style of existing rows.

---

## Skill Structure

```
skills/
  <name>/
    SKILL.md        ← required; the skill entry point
    scripts/        ← optional; shell helpers called by the skill
    references/     ← optional; supporting material
    assets/         ← optional; reusable files
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

## Portable SKILL.md Template

````markdown
---
name: <skill-name>
description: <see Description Requirements below>
---

<One-line purpose statement — what this skill does and when to use it.>

## On Invocation

<Steps to run immediately on invocation. Do not require host-specific banners or argument variables.>

## Phase 1 — <First Phase Name>

<Instructions. Keep the skill self-contained and use only capabilities available across the stated target agents.>

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
  - `autopilot`: "General autonomous wrapper — runs the core bf workflows (feature, quick, micro, review, design) without user input."
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

- [ ] **Portable frontmatter complete** — `name` and `description` are present. Do not add host-specific fields such as `model`, `allowed-tools`, or `disable-model-invocation` unless the user explicitly asked for a host-specific skill.
- [ ] **No host assumptions** — the skill does not depend on `${CLAUDE_PLUGIN_ROOT}`, Claude tool names, hooks, permission declarations, or model routing unless it is explicitly labeled host-specific.
- [ ] **ONE-question-per-turn respected** — any interactive gather phase asks one question, then waits. No batched questions anywhere in the skill.
- [ ] **Single file unless justified** — no companion files created unless the skill exceeds ~130 lines or scripts are reusable across skills.
- [ ] **README updated** — a row for the new skill is added to the `## What's inside` table in `README.md`.
- [ ] **Portability labeled** — the README row labels a portable skill as portable and does not assign it Claude-only invocation syntax.
- [ ] **Deterministic ops are in scripts** — path computation, JSON reads, stack detection, and status parsing are in shell scripts rather than left to the model to derive inline. Token-heavy bash output is piped through a reducing proxy (e.g. `rtk`) where available.
- [ ] **Description is action-triggered** — starts with "Use when…" or equivalent trigger phrasing; not a description of internals.
- [ ] **Portable resources** — references and scripts resolve relative to the skill directory and are included with the skill. Do not rely on files outside the skill directory for portable behavior.
- [ ] **Agent use is portable or explicit** — if the skill depends on multi-agent orchestration, label the required host or provide a useful single-agent fallback.
- [ ] **Host-neutral invocation** — do not require slash-command syntax or a skill invocation feature that is not part of the Agent Skills format.
- [ ] **Edge cases listed** — at least a stub `## Edge Cases & Errors` table covering the most obvious failure modes.
- [ ] **Run once on a real input** — invoke the skill end to end on one real artifact (a real doc, branch or repo, not a fixture) before handing it to review. Structural checks pass on a skill that is still awkward to use; one real run surfaces that before review cycles are spent polishing its text. Note what the run changed, or that it changed nothing.
- [ ] **Free-form arguments reach scripts intact** — if the skill hands its arguments (paths, `#N`, URLs) to a script, pass them on stdin through a quoted heredoc (`<<'BF_ARGS'` … `BF_ARGS`), never on the command line: the arguments are substituted into the text before the shell parses it, so a space splits a path, `#123` becomes a comment, and a quote — even inside `"$ARGUMENTS"` — breaks the command. Write smoke cases for a path with spaces, parentheses, a quote and a leading `#` in the same change that adds the script. The check below must print `clean`:

```bash
grep -nE 'bash .*\$ARGUMENTS' <new-skill-dir>/SKILL.md || echo "clean"
```
- [ ] **No foreign path namespaces** — a skill drafted from another plugin's file carries its path literals across silently. Remove host-specific paths or document an explicit host-only target.

```bash
grep -rn -e '.claude/skills' -e '.claude/plugins' -e '$HOME/.claude' -e 'CLAUDE_PLUGIN_ROOT' <new-skill-dir> || echo "clean"
```
