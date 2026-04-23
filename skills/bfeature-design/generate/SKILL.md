---
name: bfeature-design-generate
description: Agent sub-skill that reads a Q&A transcript and produces a structured system-design document with diagrams. Invoked by the bfeature-design orchestrator.
disable-model-invocation: true
argument-hint: [qa-file-path] [output-doc-path]
model: opus
---

Produce a complete, shareable system-design document from the gathered Q&A transcript.

## Input

The prompt contains two absolute file paths:
1. **Q&A file path** — the transcript written by the orchestrator after the gather phase.
2. **Output doc path** — where the finished design document must be written.

Read the Q&A file first, before doing anything else. If the Q&A file is missing or empty, emit the error string:

```
ERROR: Q&A file not found or empty at <path>. Cannot generate design doc.
```

Then exit without writing anything. The orchestrator's retry logic handles recovery.

If the prompt includes a `FEEDBACK:` block (revision mode), Read the existing doc at the output path first, then apply the feedback and overwrite the same file (see Revision mode below).

## Step 0 — Do NOT explore the codebase

**Hard rule:** Do not read, Glob, Grep, or otherwise inspect the current project's codebase. This skill produces a high-level design document from the Q&A alone — it is codebase-agnostic by design. Named systems, services, and APIs mentioned in the Q&A are treated as architectural concepts, not as files to locate. If any system is unknown or unresolved, flag it in the "Open questions / risks" section based on the Q&A context, not on filesystem inspection.

## Step 1 — Diagram tool selection

Use this decision tree, in order:

1. Use `ToolSearch` to resolve schemas for the five Excalidraw MCP tools:
   `mcp__claude_ai_Excalidraw__create_view`, `mcp__claude_ai_Excalidraw__export_to_excalidraw`,
   `mcp__claude_ai_Excalidraw__read_checkpoint`, `mcp__claude_ai_Excalidraw__read_me`,
   `mcp__claude_ai_Excalidraw__save_checkpoint`.

2. If schemas resolve successfully: use `create_view` (and optionally `export_to_excalidraw`) to produce at least one diagram. Embed the returned shareable link in the doc. A descriptive caption is **mandatory** immediately above or below every diagram link.

3. If `ToolSearch` returns no matches, OR if any Excalidraw call fails mid-generation: switch to Mermaid for **all** diagrams in the doc. Do not mix Excalidraw links and Mermaid blocks in the same document. Add a note at the top of the Diagrams section:
   - If never available: "Diagrams rendered in Mermaid — Excalidraw not available at generation time."
   - If it failed mid-generation: "Diagrams rendered in Mermaid — Excalidraw encountered an error mid-generation."

4. Mermaid diagrams go in ` ```mermaid ` fenced code blocks.

5. Choose diagram type based on content:
   - Sequence diagrams for request / response flows
   - Component or graph diagrams for topology and service relationships
   - State diagrams for lifecycle or FSM behaviour

## Step 2 — Write the design doc

### Tone and audience

**Hard rule — stakeholder document:** This doc is written for a non-technical or mixed audience (stakeholders, product, leadership). It must be:

- **Free of implementation specifics:** no code snippets, no internal tool names (no mentions of bfeature, Claude, or any internal tooling), no framework or library references, no file paths or codebase details.
- **Concept-level, not code-level:** describe systems and interactions in terms of responsibilities, data flows, and trust boundaries — not classes, endpoints, or database schemas.
- **Decision-enabling, not solution-prescribing:** the goal is to align stakeholders on the problem and the high-level approach. Detailed implementation planning comes after stakeholder review.
- **Jargon-light:** define any technical term the first time it appears. Avoid abbreviations without explanation.

Compose all sections in memory, then write the complete document to the output path in a **single Write call**. Do not write partial content or multiple files.

Required sections (H1 title, then H2 for each subsequent section):

| Section | What goes here |
|---|---|
| Title (H1) | Descriptive title derived from the idea — your phrasing, not a copy-paste of `$ARGUMENTS` |
| Summary | 2–4 sentences: what this design covers, why it matters, what the outcome is |
| Context & problem | Current state, pain points, and why a change is needed |
| Actors & systems | Who and what is involved; include roles, permissions, and ownership |
| Proposed design | Data flow, service responsibilities, trust / auth model, and key decisions with rationale — concept-level, no code |
| Diagrams | All diagrams with mandatory captions |
| Alternatives considered | Other approaches and why they were ruled out or deferred |
| Open questions / risks | Unresolved design questions, known risks, and mitigation ideas |
| Notes / Unknowns | Only present if there are unresolved systems or concepts from the Q&A |

Q&A → doc section mapping (guidance, not a strict contract):

| Q&A topic | Primary doc section |
|---|---|
| Problem framing / actors | Context & problem, Actors & systems |
| Systems / services involved | Actors & systems, Proposed design |
| Data flow | Proposed design, Diagrams |
| Trust / security | Proposed design (auth sub-section) |
| Failure modes | Open questions / risks |
| Alternatives considered | Alternatives considered |
| Constraints | Proposed design, Notes / Unknowns |
| Success criteria | Open questions / risks |

## Output

Write the finished markdown to the **output path** provided in the prompt. One Write call. No other files written. No git operations.

## Revision mode

If the prompt includes a `FEEDBACK:` block:
1. Read the existing doc at the output path.
2. Apply the feedback — update, expand, or restructure as requested.
3. Overwrite the same file with the revised doc. Do not produce a diff. Do not write a new filename.

Here is the input:
$ARGUMENTS
