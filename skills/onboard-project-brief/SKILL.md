---
name: onboard-project-brief
description: "Use when someone wants a quick orientation on a repository — 'onboard me', 'what does this repo do', 'give me the gist', 'I just joined, where do I start'. One cheap pass, no questions: writes a single ~60–80-line page (what it does, main blocks, stack, glossary, key commands, where to look first) and prints it in full. The full multi-lesson course is command-only: /bf:onboard-project. For documenting and judging every build unit use bf:arch-audit."
model: sonnet
disable-model-invocation: false
argument-hint: "[path]"
allowed-tools: Read, Write, Grep, Glob, Agent, Bash(bash *), Bash(git *), Bash(mkdir *), Bash(rtk *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

One page that gets a newcomer oriented. It asks nothing and runs inline; the full course stays an explicit `/bf:onboard-project`.

**Hard rules.**
- **Every claim has a source** (`path` or `path:line`) **or is marked *inferred*.**
- **Never run a discovered command.** Commands are quoted from where they were found.
- **Write only** the page at `output_path`. Never edit the target repo's `.gitignore` or any other file.

## On Invocation

Print the banner as plain text: `── bf:onboard-project-brief ─────────────────────────────────`

One probe call. `$ARGUMENTS` is an optional subdirectory to scope to; omit it for the whole repo.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard-project/scripts/onboard-probe.sh" brief - <<'BF_ARGS'
$ARGUMENTS
BF_ARGS
```

On `{"error":…}` follow the Edge Cases table: free text that is not a path falls back to a whole-repo run; any other error is one line and no file. Otherwise keep `repo`, `sha`, `path`, `layout`, `needs_agent`, `output_path`, `units`, `hot_dirs` and `signals`. The probe does all counting and grouping — render its fields, do no arithmetic.

## Gather

Read the leading `signals.docs.sample` entries (the root README first), the leading `signals.manifests.sample` entries, and only as much source as it takes to name the entry points and the domain terms. Stay shallow: this is a skim, not a survey.

If `needs_agent` is true, start one read-only `Explore` agent named `brief-groups`. Give it `units.groups` from the probe and ask for a one-line purpose per group, returned as text only, no file contents. It must not run `detect-units.sh` or build its own grouping. Wait for it, then use its lines in Main blocks. Otherwise do everything inline.

## Page

Write these seven sections in order, about 60–80 lines in all:

1. **What it does.** 2–3 sentences, each with a source; guesses marked *inferred*.
2. **Main blocks.** List `units.shown`, then one line per entry of `units.groups`: "+N more under `<dir>` (e.g. a, b, c)" — N is `remaining`, the names are `examples` (leave out "e.g." when empty). Then an ASCII diagram of 15 lines or fewer.
3. **Stack.** From the manifests, root-level first.
4. **Glossary.** At most 5 domain terms, each with a source.
5. **Key commands.** At most 6, each labelled "found in `path:line`, not run".
6. **Where to look first.** At most 5 entries: entry points, `hot_dirs` (most-changed areas), key docs.
7. **Next step.** Offer the full course: `/bf:onboard-project` builds a complete multi-lesson course for this repo.

Stamp the page `<repo>@<sha>` and today's date. `mkdir -p` the directory of `output_path`, write the page there (overwriting any earlier run), then print the page in full in the terminal.

The brief lives in `.bf/onboard-brief/`, one page per repo (plus one per scoped subtree), rather than in the course's per-course `.bf/onboard/<slug>` facts directory.

## Edge Cases

| Condition | Handling |
|-----------|----------|
| `not_a_directory` and the argument is not a path (free text such as "give me the gist") | Re-run the probe with empty input, for the whole repo, and say in one line that the text was not used as a path. |
| Any other `error` from the probe (`not_a_git_repo`, `jq_not_found`, `path_outside_repo`, `not_a_directory` for a path-like argument) | One line naming the error; write no file. |
| `layout` = `empty` | Render only What it does (from docs, else "no content found"), Key commands and Next step, and say the repo is empty. |
| `layout` = `flat` | Render every section; Main blocks says the layout is flat or single-package; no diagram. |
| `layout` = `single` | Render every section; no diagram. |
| `layout` = `dir` | Call them "top-level directories", say the layout is *inferred* from directory names, and mark the diagram *inferred* too. |
| `layout` = `build` | Normal page; diagram of 15 lines or fewer. |
| `needs_agent` is true | Start the `brief-groups` agent as above; if it fails, show the groups without purposes and say so. |
| `path` is non-empty | Scoped run; the page is the subtree's own file and never overwrites the whole-repo brief. |
| No command found for a stack | Omit Key commands entries rather than guess; never invent one. |
