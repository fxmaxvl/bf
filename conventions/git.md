# Git Commit Conventions

Generate a concise, one-sentence Git commit message based on the staged changes.
Follow the Conventional Commits specification and choose the correct prefix based on the type of changes made.

## Requirements

- Only consider staged, versioned files (ignore unversioned and `.gitignore` files)
- Analyze the code changes to determine the most appropriate prefix:
  - `feat:` — new features or functionality
  - `fix:` — bug fixes
  - `docs:` — documentation changes only
  - `style:` — formatting, missing semicolons, etc. (no code change)
  - `refactor:` — code changes that neither fix bugs nor add features
  - `test:` — adding or modifying tests
  - `chore:` — maintenance tasks, build changes, dependency updates
  - `perf:` — performance improvements
  - `ci:` — continuous integration changes
- End the message with a newline followed by `#pr` if this is the first commit message in this branch
- If there are no versioned changes, output exactly `---`

## Examples

### Good commit messages:

```
feat: add similarity search for related documents
fix: resolve indexing timeout for large articles
docs: update API documentation for answer generation
test: add unit tests for CleanTextUtil
chore: upgrade typescript to 5.0
```

### With #pr tag (first commit in branch):

```
feat: implement new vector search algorithm
#pr
```

### No changes:

```
---
```

## Guidelines

- Keep messages under 72 characters when possible
- Use imperative mood ("add" not "added" or "adds")
- Don't capitalize the first letter after the colon
- No period at the end of the message
- Be specific about what changed, not why it changed
- Do not add to staged changes, only analyze what is already staged
