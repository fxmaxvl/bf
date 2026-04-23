## Conventions — read before acting

Before writing code, committing, writing tests, reviewing code, or making architectural decisions — read the relevant convention file first. Do not infer conventions from git history or surrounding code.

To find a convention file, use Glob with `**/.claude/conventions/<name>.md`. Use the closest match to the current working directory. If not found, fall back to `~/.claude/conventions/<name>.md`.

| Action | Convention file |
|--------|----------------|
| Writing or modifying code | `dev.md` |
| Writing or modifying tests | `testing.md` |
| Committing | `git.md` |
| Designing architecture | `architecture.md` |
| TypeScript / JavaScript work | `typescript.md` |
| Reviewing code | `code-review.md` |

Also read any technology-specific convention files that match the project's stack.

## Getting help

- Ask ONE clarifying question at a time. Never batch multiple questions in a single response.

## Skills

Reusable skills live in `./skills/`. Each skill has a `SKILL.md` with frontmatter (name, description, optional model routing).

### Entry points

- `/bfeature` — list all available commands
- `/bfeature-full <idea>` — full workflow for new features
- `/bfeature-quick <idea>` — lightweight workflow for small changes
- `/bfeature-design <idea>` — produce a shareable system design document
- `/bfeature-gh` — pick a GitHub issue, then kicks off bfeature
- `/bfeature-jira` — pick a Jira ticket, then kicks off bfeature
- `/session-summary` — generate a session summary
