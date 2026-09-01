---
name: install-guidelines
description: Use when the user wants the bf engineering guidelines active outside bf — "install the guidelines", "make them apply everywhere", "add bf guidelines to my CLAUDE.md". Copies the plugin's guidelines convention to the user tier and imports it from the global CLAUDE.md so it loads in every Claude Code session. Idempotent.
model: sonnet
disable-model-invocation: false
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash(bash *), Bash(mkdir *), Bash(cp *), Bash(diff *), Bash(cat *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Install the engineering guidelines (`conventions/guidelines.md`) at the user tier so they apply in every Claude Code session on this machine, not only inside bf skills.

## On Invocation

Print banner (plain text, not in a code block):

```
── bf:install-guidelines ────────────────────────────────
```

Then probe the current install state — one call, no writes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/install-guidelines/scripts/probe.sh" "${CLAUDE_PLUGIN_ROOT}"
```

It returns a single JSON object with `src`, `dest`, `import`, `claude_md_writable`, and the resolved paths. Every branch below keys off those fields — do not re-derive any of them by hand.

If `src` is `missing`, abort and report `src_path`. Nothing else runs.

## Phase 1 — Install the convention file

Branch on `dest`:

| `dest` | Action |
|--------|--------|
| `current` | Skip the write. Report "already current". |
| `absent` | `mkdir -p <dest_dir>` then `cp <src_path> <dest_path>`. |
| `differs` | Show `diff <dest_path> <src_path>`, then ask ONE question (below) and act on the answer. |

On `differs`, ask exactly this and wait — a user-tier file **overrides** the plugin copy under the 3-step Convention Lookup, so it may have been customized deliberately. Never overwrite it silently:

> `~/.bf/conventions/guidelines.md` already exists and differs from the plugin copy. Overwrite it, keep the existing one, or abort?

- **Overwrite** → copy over it, continue to Phase 2.
- **Keep** → leave it, continue to Phase 2 (the import still needs wiring).
- **Abort** → stop, write nothing, report what was left untouched.

## Phase 2 — Wire the import

Branch on `import`:

| `import` | Action |
|----------|--------|
| `present` | Skip. Report "already imported". |
| `absent` | Append `<import_line>` to `<claude_md>` as its own line, preceded by a blank line. |
| `no_claude_md` | Create `<claude_md>` containing just `<import_line>`. |

If `claude_md_writable` is `false`, do not attempt the write. Report the failure and print `<import_line>` verbatim so the user can add it themselves.

## Phase 3 — Report

Print one line per path stating exactly what happened — `written`, `already current`, `already imported`, `kept existing`, or `failed`. Do not claim success for a step that was skipped or that failed.

Close with: the import takes effect in a **new session** (or after `/clear`) — it is not retroactive to the current one.

Project-scoped overrides are a manual copy into `<project>/.bf/conventions/guidelines.md`; this skill does not manage them.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `${CLAUDE_PLUGIN_ROOT}/conventions/guidelines.md` missing | Abort before any write; report the resolved `src_path` |
| `~/.claude/CLAUDE.md` absent | Create it containing only the import line |
| Import already present in any equivalent form | Report "already imported", skip, do not append a second line |
| `~/.bf/conventions/guidelines.md` identical to source | Skip the write, report "already current" |
| `~/.bf/conventions/guidelines.md` differs | Show the diff, ask ONE question (overwrite / keep / abort) |
| `~/.claude/CLAUDE.md` not writable | Report the failure and print the exact line the user must add manually |
| Asked to edit the guideline text itself | Out of scope — that is a direct edit to `conventions/guidelines.md` in the plugin repo |
| Any path under `~/.claude/plugins/cache/**` | Read-only. Never write there; the repo is the source of truth |
