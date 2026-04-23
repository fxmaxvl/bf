## Conventions — read before acting

This applies to **all work in this repo**, regardless of whether a skill is involved.

Before writing code, committing, writing tests, reviewing code, or making architectural decisions — read the relevant doc first. Do not infer conventions from git history or surrounding code. Always check the doc.

To find a convention file, use Glob with `**/.claude/conventions/<name>.md`. Use the closest match to the current working directory. If not found, fall back to `~/.claude/conventions/<name>.md`.

**Step 1 — Action-specific convention:** Read the file that matches the action:

| Action | Convention file |
|--------|----------------|
| Writing or modifying code | `dev.md` |
| Writing or modifying tests | `testing.md` |
| Committing | `git.md` |
| Designing architecture | `architecture.md` |
| TypeScript / JavaScript work | `typescript.md` |
| Reviewing code | `code-review.md` |

**Step 2 — Technology conventions:** Detect the project's tech stack (check for `tsconfig.json`, dominant file extensions, `package.json` scripts, etc.) and read any additional technology convention files that apply. For example, if the project uses TypeScript, also read `typescript.md` — even if the action-specific file is `testing.md`.

---

## Getting help

- ALWAYS ask for clarification rather than making assumptions.
- **CRITICAL: Ask ONE question at a time. Never batch multiple questions into a single response. If you have 3 things to clarify, ask the first one, wait for the answer, then ask the next.** This is a hard rule, not a suggestion.

## Skills

Reusable skills live in `./skills/`. Each skill has a `SKILL.md` with frontmatter (name, description, optional model routing).

### Entry points

- `/bfeature:menu` — list all available commands
- `/bfeature:full <idea>` — full workflow for new features
- `/bfeature:quick <idea>` — lightweight workflow for small changes
- `/bfeature:design <idea>` — produce a shareable system design document
- `/bfeature:gh` — pick a GitHub issue, then kicks off bfeature
- `/bfeature:jira` — pick a Jira ticket, then kicks off bfeature
- `/bfeature:session-summary` — generate a session summary
