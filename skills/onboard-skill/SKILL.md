---
name: onboard-skill
description: "Use when the user provides a URL to an external skill and wants to steal and adapt it for the bf plugin. Fetches the source skill, analyzes which parts to port per the user's instructions, identifies bf convention gaps, and hands off a complete design spec to bf:write-skill."
model: opus
disable-model-invocation: false
argument-hint: "<url> <instructions about what to onboard>"
allowed-tools: Read, WebFetch, Bash(gh *), Task
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules including the **one-question-per-turn** rule that governs every interactive phase below.

Steal a skill from an external source, adapt it to bf conventions, and hand it off to `bf:write-skill`.

## On Invocation

Print banner (plain text, not in a code block):

```
── bf:onboard-skill ─────────────────────────────────────
```

Parse the argument:
- **URL** — first token that starts with `http` or `github.com`
- **Instructions** — everything after the URL (what parts to onboard, what to skip, any naming preference)

If either is missing, ask ONE question for the missing piece before proceeding.

## Phase 1 — Fetch

Retrieve the source skill file:

- If the URL is a `github.com` blob URL (e.g. `https://github.com/<org>/<repo>/blob/<branch>/path/to/SKILL.md`):
  - Convert to API form: `gh api repos/<org>/<repo>/contents/<path>?ref=<branch> --jq .content | base64 -d`
  - Fall back to `WebFetch` if `gh` is unauthenticated for that repo.
- Otherwise: `WebFetch` the URL directly.

Print one line: `Fetched: <url> (<N> lines)`

## Phase 2 — Analyze

Read the fetched skill against the user's instructions. Produce a compact analysis block:

```
## Source Analysis
Origin: <url>
Source plugin: <detected plugin name, e.g. vs, cowork, or unknown>
Skill purpose: <one sentence>

Parts to onboard (per instructions):
- <phase or section>: <what it does>
- ...

Parts to skip:
- <phase or section>: <reason>

Adaptation gaps (bf convention deltas):
- Artifact path: <source convention> → .bf/ lookup
- Convention lookup: <source pattern> → plugin-main.md 3-step lookup
- Tool availability: <tools used in source not in bf allowed-tools, e.g. octocode>
- One-question rule: <any phases that batch questions — flag them>
- Other: <anything else that needs changing>
```

Print the analysis block. Proceed without waiting for approval.

## Phase 3 — Adapt

Synthesize a complete bf design spec from the analysis. This is the spec that will be passed to `bf:write-skill`. Shape:

```
## bf:onboard Design Spec — <proposed skill name>

### Trigger patterns
<when should this skill be invoked>

### Overview
<what the adapted skill does, in bf terms>

### Phases
<for each onboarded phase: name, what it does, any tool or convention changes from the source>

### Artifact path
<where outputs go, using .bf/ convention>

### Allowed tools
<list>

### Model
<opus | sonnet | haiku — justify if non-default>

### Boundaries / when NOT to use
<lifted or adapted from source, if present>

### Edge cases
<lifted or adapted from source, plus any new ones introduced by the adaptation>
```

## Phase 4 — Hand Off

Invoke `bf:write-skill` passing the full design spec as the argument. `bf:write-skill` will produce the `skills/<name>/SKILL.md` and update `README.md`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| URL is private GitHub and `gh` is unauthenticated | Fall back to WebFetch; if that also fails, ask the user to paste the raw skill content |
| URL points to a non-SKILL.md file | Proceed — analyze whatever is fetched as the source material |
| Instructions are too vague to determine what to skip | Pick the most literal interpretation, state the assumption in the analysis block, proceed |
| Source skill uses tools unavailable in bf (e.g. `octocode`, MCP-specific tools) | Flag in adaptation gaps; propose the closest bf equivalent in the design spec |
| Proposed skill name conflicts with an existing skill | Note the conflict in the spec and let `bf:write-skill` handle the overwrite prompt |
