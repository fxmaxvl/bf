# Quality Gates Convention

Applies to any skill that needs to detect, run, or document quality gates.

## Step 1 — Load stack info

Run the helper scripts:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/detect-stack.sh"
```

This gives you `type`, `test_commands`, `lint_command`, `lint_fix_command`, `monorepo`, `workspaces`, and `scope_template`. Use these values directly — do not re-detect or hardcode commands.

## Step 2 — Load stack-specific conventions

- **If `type` is `node` or `typescript`** → read `${CLAUDE_PLUGIN_ROOT}/conventions/typescript.md` for any project-specific overrides to lint and test commands.
- **All projects** → read `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md` for test requirements.

## Step 3 — Apply monorepo scoping

If `monorepo` is `true`, scope test and lint commands to the affected package using `scope_template`. Do not run commands for the whole monorepo.

## Documenting quality gates (for the plan phase)

Include a **"Quality Gates"** section in the plan file using the commands resolved above. Use this format — substitute actual resolved commands, never hardcode:

```markdown
## Quality Gates

- **Tests:** `<test_command>` [(scoped to `<package>` — monorepo)]
- **Lint:** `<lint_command>` [/ auto-fix: `<lint_fix_command>`]
```
