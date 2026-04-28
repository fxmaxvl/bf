---
name: quality-gate
description: Resolve test and lint commands (stack detection + convention overrides + monorepo scoping). Writes the Quality Gates section to the plan file during the plan phase; outputs resolved commands during verify.
disable-model-invocation: true
allowed-tools: Read, Bash
model: sonnet
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

## Step 1 — Load state and stack info

Run the helper scripts:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/state-ops.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/bfeature/scripts/detect-stack.sh"
```

This gives you `phase`, `paths.plan`, `type`, `test_commands`, `lint_command`, `lint_fix_command`, `monorepo`, `workspaces`, and `scope_template`. Use these values directly — do not re-detect or hardcode commands.

Note: `detect-stack.sh` may re-run even if the calling skill (plan or verify) already ran it. This is a known tradeoff of inline invocation — the sub-skill shares conversation context but not shell state, so scripts must be re-executed rather than referencing prior output.

## Step 2 — Apply stack-specific convention overrides

- **If `type` is `node` or `typescript`** → read `${CLAUDE_PLUGIN_ROOT}/conventions/typescript.md` for any project-specific overrides to lint and test commands.
- **All projects** → read `${CLAUDE_PLUGIN_ROOT}/conventions/testing.md` for test requirements.

## Step 3 — Apply monorepo scoping

If `monorepo` is `true`, scope test and lint commands to the affected package using `scope_template`. Do not run commands for the whole monorepo.

## Step 4 — Phase-aware output

**If `phase` is `plan`:** Append a **"Quality Gates"** section to `paths.plan`. Substitute actual resolved commands — never hardcode:

```markdown
## Quality Gates

- **Tests:** `<test_command>` [(scoped to `<package>` — monorepo)]
- **Lint:** `<lint_command>` [/ auto-fix: `<lint_fix_command>`]
```

**If `phase` is `verify`:** State the resolved test and lint commands clearly in the conversation — do not write to any file. The calling skill uses these to run the gates.
