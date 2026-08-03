# codex-probes

This directory holds tiny, self-contained candidate skill files that isolate specific mechanical unknowns about running the `bf` plugin's skill format under Codex CLI instead of Claude Code.

**Every file in this directory is an untested candidate.** None of them has ever been executed by Codex CLI. Each is a hypothesis about Codex's behaviour, not a verified artifact — this label is repeated as the first line of every probe's own body so it travels with the file if copied elsewhere.

See `docs/codex-compatibility.md` for the full portability analysis these probes support, including the numbered Verification Checklist that explains exactly how to run each probe and what each possible outcome means.

## Contents

- `probe-1-nested-handling/bf-probe-parent/{SKILL.md,child/SKILL.md}` — does a nested `SKILL.md` cause Codex any trouble (harmlessness), not whether Codex can discover it (capability)?
- `probe-2-plugin-root/bf-probe-pluginroot/SKILL.md` — does Codex expose an equivalent of Claude Code's `${CLAUDE_PLUGIN_ROOT}`?
- `probe-3-arguments/bf-probe-arguments/SKILL.md` — does Codex substitute an `$ARGUMENTS`-equivalent token?
- `probe-4-frontmatter/bf-probe-frontmatter/SKILL.md` — does Codex's frontmatter parser tolerate, ignore, or reject bf's non-standard keys?

## How to install a probe into Codex

Codex documents two skill discovery locations: a global one (`~/.agents/skills`) and a repo-local one (`.agents/skills`). To try a probe, copy or symlink its skill directory into one of those locations, e.g.:

```
mkdir -p ~/.agents/skills
cp -r codex-probes/probe-2-plugin-root/bf-probe-pluginroot ~/.agents/skills/
```

Then invoke the skill by name (`bf-probe-pluginroot`) from a Codex session and observe the transcript per the checklist entry in `docs/codex-compatibility.md`.

## Why this directory is not under `skills/`

This directory sits **deliberately outside** the `bf` plugin's `skills/` tree (and outside `.claude/`), so Claude Code does not discover or register any of these files as real skills. A future contributor should **not** "tidy" this directory into `skills/` — doing so would make these untested candidates discoverable and invocable inside Claude Code, which defeats their purpose.
