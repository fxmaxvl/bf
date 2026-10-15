---
name: visualize
description: Use when you want an interactive, drill-down diagram of a system — "visualize this architecture", "interactive diagram of the design", "drill-down view of the system". Input is a bf:arch-audit doc (an existing system) or a bf:design doc (a planned one); output is a committable LikeC4 model and one self-contained HTML file.
model: opus
disable-model-invocation: false
argument-hint: <path to *-arch-audit.md or *-design.md>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash *), Bash(mkdir *), Bash(open *), Bash(xdg-open *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Print the banner as plain text: `── bf:visualize ───────────────────────────────────`

If `$ARGUMENTS` is empty, say that a doc path is required and stop. Do not guess a doc. This skill asks no questions; it runs straight through.

**Hard rule: never invent architecture.** Draw only what the doc states. When the doc names something but leaves its kind, parent or connections unclear, make it an element tagged `#tbd` whose description holds the open question. When no doc content supports a level, that level gets no view.

The script `build.sh` is the only script you call. It counts attempts, edits the model's marker line and cleans up after failures, so none of that is yours to do by hand.

## 1. Init

Run once, **before writing any file**:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/visualize/scripts/build.sh" --init --doc <doc>
```

If it prints `{"error":…}`, print the `detail` and stop (`nothing_to_visualize` means the doc has nothing to draw). Otherwise read `kind`, `slug`, `model_path`, `build_dir` and `mapping_path` from the JSON. Never run `--init` again mid-loop: it resets the attempt counter and the first-write fact.

## 2. Map the doc to a model

Read the doc and `${CLAUDE_PLUGIN_ROOT}/skills/visualize/references/dsl.md`.

- **`kind` = `arch-audit`.** Code structure is not runtime structure, so classify every layer first. Each layer is one of: a runtime container (a deployable or process), a component inside a container, a datastore or queue, an external dependency, or *not runtime* (a library, shared code or build-only unit: fold it into the component that uses it, or leave it out). Write the table to `mapping_path` (`build_dir` already exists). Cross-subsystem dependencies from the audit's merge phase become relationships.
- **`kind` = `design`.** *Actors & systems* gives the context level; *Proposed design* gives the containers, their responsibilities and the relationships (the data flows). Flows in *Proposed design* and *Diagrams* become `dynamic view`s. Parse Mermaid sequence diagrams when present. If *Diagrams* holds only Excalidraw links, derive flows from the prose and never fetch a link.
- Quote the doc section each element came from in its description (`from: Proposed design`).
- **Zero elements** (for example an arch-audit with only non-runtime layers): print "nothing to visualize" and stop. Write no `.c4`.

## 3. Write the model

Write `<slug>.c4` to `model_path`, containing `model` and `views` blocks only, never a `specification` block. Use the domain override's kinds where they apply and the base kinds otherwise.

- One `index` view, plus one `view <x> of <x>` per element with children.
- Split a view that would show more than about 20 elements into focused views.
- Keep each `dynamic view` at one nesting level (no element together with its own descendant).

The `.c4` is written outside `.bf/`, as the named exception in `plugin-main.md` allows. For `arch-audit` input `model_path` is under `docs/architecture/`: `mkdir -p` it first and tell the user the file is there so it can be committed. For `design` input it sits next to the doc.

## 4. Build loop

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/visualize/scripts/build.sh" --doc <doc>
```

It allows 3 attempts in total and reports `attempt` and `final`.

- `ok` is true: go to step 5.
- `retryable` is true and `final` is false: fix only the `model` and `views` blocks of `<slug>.c4` from `errors` and `warnings` (warnings are failures), then run it again.
- `final` is true and `ok` is false: print the diagnostics and a short failure summary, and stop. Do not open any HTML. If `sensitive_reminder` is true, print the reminder from step 5 first: the `.c4` may be committed.

`build.sh` edits `<slug>.c4` itself: on a final model failure it stamps a `// bf:visualize: FAILED VALIDATION …` first line (`model_stamped` is true), and a later success strips it. It also deletes `index.html` and `mapping.md` on a final failure. Never add, edit or remove that line by hand.

## 5. Deliver

Local only: never publish, upload or offer to.

- Print the `model_path` and the `html` path, the `views`, `element_count` and `tbd_count`, all taken from the JSON, never estimated.
- Open the HTML: `open <html>` on macOS, `xdg-open <html>` elsewhere. If that fails, just print the path.
- If `sensitive_reminder` is true, print: `Reminder: review the model for sensitive details (internal service names, auth schemes, API keys) before committing or sharing it.`

## Edge Cases & Errors

| Condition | Handling |
|---|---|
| `unsupported_input` | Print the detail: the input must be `*-arch-audit.md` or a design doc (`*-design.md`, or one with `## Summary`, `## Actors & systems` and `## Proposed design`). |
| `doc_not_found`, `missing_arg` | Print the detail and stop. |
| `no_project_root` | A `*-arch-audit.md` outside `.bf/audits/` and outside git has no known repo root. Move the doc into the audited repo's `.bf/audits/`. |
| `nothing_to_visualize` | The design's *Actors & systems* section is empty. Tell the user to fill it in, or run `/bf:design` again. |
| `not_initialized` | Run state is missing: start over from step 1 with `--init`. |
| `usage` | A bug in how the script was called; fix the call. It never means the doc is wrong. |
| `source` = `spec`, error says "fix your override at …" | The user's `visualize-spec.c4` redefines a base kind or is invalid. Print the message and stop; never edit it. |
| `source` = `spec`, error says "plugin bug, please report" | The bundled base spec is broken. Print the message and stop. |
| `source` = `toolchain`, `mirror_lag` | The npm registry or mirror has not synced the pinned likec4. Print the detail. The version is pinned on purpose and no other is tried. |
| `source` = `toolchain`, `install_failed` or `verify_failed` | `npm install` failed, or the installed likec4 does not run. Print the detail and stop; the next run wipes the cache and reinstalls. |
| `jq_missing` | `jq` is not installed. Tell the user to install it. |
| `source` = `toolchain`, `no_node` | Node.js and npm are missing. Tell the user to install them. |
| `source` = `staging` | The model file is missing or likec4 failed without a diagnostic. Print it and stop. |
| Failed after 3 attempts | Keep the stamped `.c4`, print the remaining diagnostics, leave no `index.html`, do not open anything. |
| An earlier run was abandoned mid-loop | The next `--init` resets the state, so the counter starts again at 1. |
| Opening the HTML fails | Print the path. |
| Design doc is named `<name>-design-<N>.md` | The slug is `<name>-<N>`, so it never overwrites another design's model. |
| Doc is not in a git repo (design input) | The build goes to `~/.bf/visualize/<slug>/`; the model still sits next to the doc. |
| The HTML needs the network | The bundle lazily imports Mermaid from `cdn.jsdelivr.net` and contains `fetch(` calls that have not been traced. Views checked so far work offline, and the HTML opens over `file://`. |
| Step-by-step playback of a dynamic view | Not confirmed in the shipped bundle. Treat it as a known limitation, not a failure. |
