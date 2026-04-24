---
name: design
description: Produce a shareable system-design document (with diagrams) from a high-level idea via interactive Q&A. Standalone — no git, no branches, no PR. Optionally seeds /bfeature.
model: opus
disable-model-invocation: false
argument-hint: [idea description]
allowed-tools: Read, Write, Glob, Grep, mcp__claude_ai_Excalidraw__create_view, mcp__claude_ai_Excalidraw__export_to_excalidraw, mcp__claude_ai_Excalidraw__read_checkpoint, mcp__claude_ai_Excalidraw__read_me, mcp__claude_ai_Excalidraw__save_checkpoint
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Orchestrate a 4-phase design flow: Gather → Generate → Review → Optional /bfeature handoff. This skill is standalone — no git work, no build-state.json, no branches, no PR. Re-invoking the skill does NOT resume a previous session — there is no state file.

**Hard rule — one question per turn:** In every interactive phase (Gather, Review, Handoff), ask exactly one question, then stop and wait for the answer. Never batch two or more questions in a single response, even when transitioning between steps.

**Hard rule — no codebase access:** This skill is codebase-agnostic. Do not read, Glob, Grep, or inspect any files in the current project. The design document is produced entirely from the Q&A. Named systems and services are treated as architectural concepts, not as code to locate.

## Sub-skill Resolution

Sub-skills are **not registered** with the Skill tool and cannot be invoked via `Skill(name)`. They are located at `${CLAUDE_SKILL_DIR}/gather/SKILL.md` and `${CLAUDE_SKILL_DIR}/generate/SKILL.md`. Read them directly by path; no Glob needed.

**Reading the sub-skill's SKILL.md is mandatory before executing that phase.** Never skip this step.

Two invocation patterns are used in this skill:

- **Inline** (gather, review, handoff): Read the SKILL.md and follow its instructions directly in the current conversation. Do **not** use the Agent tool.
- **Agent** (generate): Read the SKILL.md and pass its full contents as the agent's `prompt`. Always pass `model: opus`.

## Status Banners

At the start of every phase, print a banner so the user knows where they are. Print as plain text (not in a code block):

```
── design | Name ───────────────────────────────
```

The Generate banner is **required** and must include the timing note:

```
── design | Generate (may take 1–2 min) ──────────
```

## Phase Flow

```
gather (inline Q&A) → generate (opus agent) → review (inline) → handoff? (inline)
```

## On Invocation

1. If `$ARGUMENTS` is empty or whitespace-only: ask the user one question — "What do you want to design?" — and use their answer as the idea.
2. Otherwise, use `$ARGUMENTS` verbatim as the idea. Do not truncate or preprocess it, even if it is a multi-paragraph paste.
3. Compute a session timestamp in `YYYYMMDDTHH` format (e.g., `20260420T14`). Then resolve the temp directory:
   ```
   project_root=$(git rev-parse --show-toplevel 2>/dev/null) \
     && TEMP_DIR="$project_root/.claude/.bfeature-temp" \
     || TEMP_DIR="$PWD/.claude/.bfeature-temp"
   mkdir -p "$TEMP_DIR"
   ```
   The temp Q&A file path is `$TEMP_DIR/<timestamp>-design-qa.md`.

## Phase 1 — Gather

Print banner: `── design | Gather ───────────────────────────────`

1. Read `${CLAUDE_SKILL_DIR}/gather/SKILL.md` and follow its instructions **inline** in the current conversation. Pass the idea as `$ARGUMENTS`.

2. When gather returns:

   **On cancellation** (gather returns `BFEATURE_DESIGN_CANCELLED`):
   - Delete the temp Q&A file at `$TEMP_DIR/<timestamp>-design-qa.md` if it exists.
   - Print: "Cancelled — no design doc produced."
   - Exit. Do NOT write a design doc.

   **On success** (gather returns `BFEATURE_DESIGN_QA_COMPLETE` with the structured Q&A):
   - Serialize the Q&A to `$TEMP_DIR/<timestamp>-design-qa.md` using this format:

     ```markdown
     # Bfeature-Design Q&A

     ## Original Idea
     <original idea text>

     ## Clarifications
     **Q: <question>**
     A: <answer>

     **Q: <question>**
     A: <answer>
     ```

   - If the Write fails for any reason (disk full, permission denied, sandboxing, etc.), abort immediately with a clear error:

     ```
     Cannot write Q&A transcript to $TEMP_DIR/<timestamp>-design-qa.md — <reason>. Cannot continue.
     ```

     Do NOT silently continue without the transcript.

3. Proceed to Phase 2.

## Phase 2 — Generate

Print banner: `── design | Generate (may take 1–2 min) ──────────`

1. **Derive a slug** from the original idea:
   - Convert to kebab-case and ASCII characters only (strip accents and non-ASCII).
   - Remove common filler words: a, an, the, of, to, in, for, on, at, by, with, and, or, but.
   - Cap at 40 characters, truncating at the nearest **word boundary before** the 40-char limit (never cut mid-word).
   - If the result is empty, too short (≤ 3 chars), or consists only of filler, use `design-<YYYYMMDD>` as the slug (e.g., `design-20260420`).

2. **Compute the output path:**
   ```
   <cwd>/<slug>-design.md
   ```
   Use the current working directory where the skill was invoked — NOT `git rev-parse --show-toplevel`. Never derive the path from the git root.

3. **Handle filename collisions:** If `<slug>-design.md` already exists in cwd, try `<slug>-design-2.md`, `<slug>-design-3.md`, and so on until a free name is found. Never silently overwrite an existing file. Inform the user: "Found an existing file; saved as `<new-name>`."

4. **(Optional) Confirm the slug:** Before invoking the agent, show the user the derived slug and ask if they want to override it. One short question — not a full Q&A. If the user overrides, re-apply the collision check.

5. **Invoke the generate agent:**
   - Read `${CLAUDE_SKILL_DIR}/generate/SKILL.md`.
   - Pass its full contents as an Agent prompt with `model: opus`.
   - The agent prompt must include:
     - The absolute path to the temp Q&A file from Phase 1 (`$TEMP_DIR/<timestamp>-design-qa.md`).
     - The absolute path to the target design doc file computed above.
     - No inline Q&A text — the agent reads the Q&A file itself.

6. **Retry once on failure:** If the agent returns an error, produces malformed output, or the output file is not written (or is written but is < 200 bytes as a sanity check), retry the agent call once automatically. On a second failure, abort the session:
   ```
   Generate failed after one retry: <error summary>. No design doc was written.
   ```
   Do NOT attempt a third retry.

7. **On success:** Tell the user:
   - The **absolute path** of the generated doc.
   - A brief summary: sections present, diagram count, diagram tool used (Excalidraw or Mermaid).

   Then proceed to Phase 3.

## Phase 3 — Review

Print banner: `── design | Review ───────────────────────────────`

Track a revision counter starting at 0. Increment it on each iterate round.

1. **Show a summary** of what was produced:
   - Absolute path to the design doc.
   - List of section headings present.
   - Diagram count and which tool rendered them (Excalidraw or Mermaid).

2. **Ask one question** (inline, wait for response):
   ```
   Want to iterate on the doc, or accept as-is?
   ```

3. **If the user accepts:** proceed to Phase 4.

4. **If the user wants to iterate:**

   a. Ask (one question, inline): "What would you like to change?" Collect freeform feedback.

   b. If the revision counter is ≥ 3 (i.e., this is round 3 or later), surface **once per round** before continuing:
      ```
      We've iterated a few times — would you like to accept as-is or start over from the top?
      ```
      Handle three branches:
      - **Accept:** proceed to Phase 4.
      - **Start over:** delete the current design doc, discard the current Q&A file, and return to Phase 1 with the original idea. A fresh Q&A transcript will be written to a new timestamp-based temp path.
      - **Continue iterating:** proceed to step 4c.

      This prompt appears once per round — not repeatedly within the same round.

   c. Re-invoke the generate agent:
      - Read `${CLAUDE_SKILL_DIR}/generate/SKILL.md`.
      - Pass its full contents as an Agent prompt with `model: opus`.
      - The agent prompt must include:
        - The same Q&A file path (from Phase 1).
        - The **same output doc path** (the agent overwrites in place — no new file, no diff).
        - A `FEEDBACK:` block containing the user's revision request.

   d. Increment the revision counter.

   e. Return to step 1 (show updated summary, ask iterate-or-accept again).

Do NOT delete the temp Q&A file in this phase — it must stay alive for potential further revisions. Phase 4 handles cleanup.

## Phase 4 — Optional /bfeature handoff

Print banner: `── design | Handoff ───────────────────────────────`

1. **Ask one question** (inline, wait for response):
   ```
   Do you want to kick off /bfeature with this design as the starting spec?
   ```

2. **If NO:**

   a. Delete the temp Q&A file at `$TEMP_DIR/<timestamp>-design-qa.md`. If deletion fails, warn but do not abort.

   b. Print:
      ```
      Design doc saved at <absolute path>. It's yours to share —
      paste into Confluence, link from Jira, whatever works best.
      ```

   c. Print the sensitive-data reminder:
      ```
      Reminder: review the doc for sensitive details (internal service
      names, auth schemes, API keys) before sharing externally.
      ```

   d. End the session.

3. **If YES:**

   a. Ask a **separate** one-question prompt (inline, wait for response):
      ```
      Full mode or quick mode?
        - full  = brainstorm + review-design + plan + execute + verify + review-impl + finalize
        - quick = plan + execute + verify + review-impl + finalize (no brainstorm, no review-design)
      ```
      Accept "full" or "quick" (case-insensitive).

   b. Construct the bfeature args string:
      ```
      <original idea text>

      (Design doc: <absolute path to design doc>)
      ```

   c. Delete the temp Q&A file at `$TEMP_DIR/<timestamp>-design-qa.md` **before** invoking bfeature. If deletion fails, warn but proceed.

   d. Print the sensitive-data reminder:
      ```
      Reminder: review the doc for sensitive details (internal service
      names, auth schemes, API keys) before sharing externally.
      ```

   e. Invoke bfeature via the Skill tool:
      - Full mode: `Skill("full", args="<constructed args>")`
      - Quick mode: `Skill("quick", args="<constructed args>")`

      Do NOT ask the user to paste a command manually. Do NOT read the bfeature SKILL.md directly — the Skill tool handles that.

4. Hand control to /bfeature (if YES) or end the session (if NO).

Here is the idea:
$ARGUMENTS
