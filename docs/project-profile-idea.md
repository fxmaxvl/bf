# Idea: Project Profile

## Core concept

Before generating anything, scan the host project to derive its architecture and code style as constraints. These discovered constraints take precedence over our own conventions for things like architecture and naming — our conventions fill the gaps where the project doesn't define anything.

## Hierarchy

1. **Project profile** (derived from host project scan) — binding for architecture, code style, patterns
2. **Our conventions** (`architecture.md`, `dev.md`, `typescript.md`, etc.) — apply where the project has no opinion

## Open questions

- Is the profile generated once at the start of a feature build and referenced by all phases, or does it re-run at checkpoints?
- What does the scan produce — a script output, an LLM-generated summary, or a structured doc?
- How does it interact with `detect-stack.sh` (which already does shallow stack detection)?
- Should it be cached across sessions for the same project?

## Relationship to current flow

- `detect-stack.sh` is a shallow version of this — detects test/lint commands but not architectural patterns
- `review-design` and `review-impl` are meant to catch convention violations but don't auto-discover project style
- A project profile would give all phases a shared, project-specific baseline to reason against
