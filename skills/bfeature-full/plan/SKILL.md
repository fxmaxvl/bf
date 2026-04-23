---
name: plan
description: Draft a detailed TDD blueprint and break it into iterative test-driven implementation prompts from the spec.
disable-model-invocation: true
model: opus
---

Draft a detailed, step-by-step blueprint for building this project. Then, once you have a solid plan, break it down into small, iterative chunks that build on each other. Look at these chunks and then go another round to break it into small steps. Review the results and make sure that the steps are small enough to be implemented safely with strong testing, but big enough to move the project forward. Iterate until you feel that the steps are right sized for this project.

From here you should have the foundation to provide a series of prompts for a code-generation LLM that will implement each step in a test-driven manner. Prioritize best practices, incremental progress, and early testing, ensuring no big jumps in complexity at any stage. Make sure that each prompt builds on the previous prompts, and ends with wiring things together. There should be no hanging or orphaned code that isn't integrated into a previous step.

Make sure and separate each prompt section. Use markdown. Each prompt should be tagged as text using code tags. The goal is to output prompts, but context, etc is important as well.

## Deferred work and TODOs

When a step requires a temporary solution, workaround, or deferred work (e.g., waiting on a dependency, simplifying for now), instruct the implementer to leave a discoverable comment in the code using this format:

```
// TODO(<slug>): <description of what needs to change and why>
```

The `(<slug>)` tag ties the comment to the feature so it can be collected automatically during the collect-todos phase. Every deferred item must have a comment in the code — no silent shortcuts.

Run the helper scripts to load state and detect the stack. Use Glob to find them: `~/.claude/skills/bfeature-full/scripts/`.

```
bash ~/.claude/skills/bfeature-full/scripts/state-ops.sh
bash ~/.claude/skills/bfeature-full/scripts/detect-stack.sh
```

`state-ops.sh` gives you `slug`, `build_timestamp`, `mode`, and all artifact paths including `paths.plan` and `paths.todo` where you'll write output.
`detect-stack.sh` gives you `type`, `test_commands`, `lint_command`, `lint_fix_command`, `monorepo`, `workspaces`, and `scope_template` — use these directly for the Quality Gates section below; no need to re-detect.

## Mode-aware input

- **Full mode** (`mode` = `"full"`): Read the spec from `.claude/.bfeature-temp/<build_timestamp>-<slug>-spec.md` — this is the primary input for planning.
- **Quick mode** (`mode` = `"quick"`): No spec exists. Read `.claude/.bfeature-temp/<build_timestamp>-<slug>-qa.md` directly — the Q&A is the primary input. Produce a lighter plan (3-8 todo items) since quick mode targets smaller, well-scoped changes.

## Quality gates — detect and document

Use the `detect-stack.sh` output from above. Additionally:

- **TypeScript/JavaScript project** → read `conventions/typescript.md` for any project-specific overrides to lint and test commands
- **All projects** → read `conventions/testing.md` for test requirements

Apply `scope_template` with the affected package if `monorepo` is true.

Include a **"Quality Gates"** section in `<build_timestamp>-<slug>-plan.md` that documents these commands so the verify phase has a starting point. Example:

```markdown
## Quality Gates

- **Tests:** `npm test` (scoped to `packages/foo` — monorepo)
- **Lint:** `npm run lint` / auto-fix: `npm run lint:fix`
```

## Deployment notes — multi-package monorepos

If a monorepo is detected **and** the feature touches more than one package, generate `.claude/.bfeature-temp/<build_timestamp>-<slug>-deployment.md` covering:

- **Affected packages** — list each package with a one-line description of what changes
- **Deploy order** — if packages depend on each other (e.g., proto/API package must deploy before consumers), document the required sequence
- **Coordination notes** — anything that requires timing or cross-team coordination (e.g., "session-service must be deployed before chatbot-service or attachment fields will be ignored")
- **Rollback notes** — if any change is hard to roll back (schema migrations, proto field additions), call it out

If the feature touches only one package, skip this file entirely — no empty deployment docs.

