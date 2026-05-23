---
name: research
description: Scan the local codebase to surface reuse candidates, conventions, and risk signals relevant to the current feature. Writes a ## Context block to session-log consumed by plan and do-todo.
disable-model-invocation: true
model: sonnet
allowed-tools: Read, Grep, Glob, Bash(git *), mcp__octocode__localViewStructure, mcp__octocode__localSearchCode, mcp__octocode__localFindFiles, mcp__octocode__localGetFileContent
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Run the helper scripts to load state and project root:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/detect-stack.sh"
```

`state-ops.sh` gives you `slug`, `build_timestamp`, `mode`, and all artifact paths.

## Input

Extract the primary input the same way `plan` does:

- **Full mode** (`mode` = `"full"`): Extract the `## Spec` block from `paths.spec` (= `paths.session_log`) using the Block Reading Pattern from `plugin-main.md`.
- **Quick mode** (`mode` = `"quick"`): Extract the `## QA` block from `paths.qa` (= `paths.temp`).

## Extraction step — build a research list

Parse the spec or Q&A text and collect concrete signals to look up:

- **Directory/file paths** — any path explicitly mentioned (e.g., `src/auth/`, `routes/user.ts`)
- **Module or package names** — import-style names (e.g., `@app/utils`, `shared/db`)
- **Type and interface names** — PascalCase identifiers that look like types or interfaces
- **Function or hook names** — camelCase identifiers that look like existing utilities
- **Test file patterns** — if the spec names a file, the adjacent `*.test.*` or `*.spec.*` is also a signal

Cap the research list to 15 signals. If you have more, prioritize: explicit file paths > module names > type names > function names.

## Scan step — use octocode local tools

**Tool calling contract:** every octocode call requires these fields or it will fail with InputValidationError.

```json
{
  "id": "research-01",
  "researchGoal": "Find the definition and usage pattern of AuthService",
  "reasoning": "Spec mentions AuthService — need to know its interface before planning",
  "query": "AuthService"
}
```

Use `id` values like `research-01`, `research-02`, etc. (stable, sequential).

**Routing by signal type:**

| Signal | Tool | Notes |
|--------|------|-------|
| Directory path | `mcp__octocode__localViewStructure` | Pass `path` = the dir; gets tree layout |
| File path | `mcp__octocode__localGetFileContent` | Pass `path` + `startLine`/`endLine` if large; read ≤ 80 lines per file |
| Symbol (type/function) | `mcp__octocode__localSearchCode` | Pass `query` = symbol name; inspect top 3 matches |
| Pattern / glob | `mcp__octocode__localFindFiles` | Pass `pattern` = glob; find adjacent files |

**Hard caps:**
- Read at most 10 files for content (`localGetFileContent`)
- Read at most 80 lines per file
- Run at most 8 `localSearchCode` queries

These caps prevent context bloat. If the list is exhausted, stop scanning — do not exceed them.

## Output

Append a `## Context` block to `paths.session_log` using the Block Writing Pattern from `plugin-main.md`.

If research produced usable findings:

```markdown
## Context

### Touched paths
<directories and files likely to be modified, one per line with a one-sentence description>

### Reuse candidates
<existing helpers, types, hooks, or utilities that the plan should use instead of reinventing; include file path and a one-line description>

### Local conventions
<patterns found in adjacent files: naming style, error handling, test file layout, import style — 3-8 bullet points>

### Risks
<naming collisions, patterns that conflict with what the spec implies, existing code that will need migration — omit section if none>
```

If no usable findings (the codebase is new, the directory doesn't exist yet, or all lookups returned nothing relevant):

```markdown
## Context

STATUS: NONE
No existing code found adjacent to this feature. Plan from spec/QA only.
```

Do **not** ask the user any questions. Do **not** modify any source files — this skill is read-only.
