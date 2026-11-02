# bf (Build Feature)

## Why bf?

Most AI coding tools write code first. That works for small tasks. For larger tasks, the skipped design step causes bugs, rework, and scope creep.

bf puts a fixed workflow between you and Claude. It clarifies the idea, writes a spec, and reviews the design for architectural gaps. Then it plans the work as a TDD blueprint, runs the plan, checks that tests and lint pass, and opens the PR. Each step is a checkpoint. Claude continues on its own where it can, and stops for your approval where it matters.

**The result:** less rework, fewer surprises in review, and a written record (spec, plan, todo list) that survives a context reset.

**Three modes:**
- **Full** (new features): brainstorm → spec → design review → plan → execute → verify → PR
- **Quick** (bug fixes and small changes): refine → research → plan → execute → verify → audit → review → PR
- **Micro** (focused refactors): clarify only if needed, then execute with complexity and quality guards

bf also has a standalone design tool, `/bf:design`, that writes shareable system design documents. Use it before anyone writes code, or when you must align with teammates first.

## What's inside

| Skill | Kind | What it does | When to use |
|---|---|---|---|
| `/bf:feature <idea>` | Workflow | Full brainstorm → spec → design → plan → execute → verify flow with checkpoints | You have a new idea and want to think it through before you touch code |
| `/bf:quick <idea>` | Workflow | refine → research → plan → execute → verify → audit → review → finalize. It skips only brainstorm and design review | You know roughly what to do and want it done |
| `/bf:micro <idea>` | Workflow | Focused refactor with complexity and quality guards | A small, scoped change: one function or one file to clean up |
| `/bf:bug-fix <symptoms>` | Workflow | Parallel root-cause hunt, then a decide-gated diagnosis and fix. It asks you nothing, except to stop before an out-of-repo or destructive fix | Something is broken and you want a fast, autonomous fix |
| `/bf:bug-hunt [--lenses …] [--repro] [path \| --repo \| --pr <n>]` | Workflow | Runs isolated hunter agents in parallel, one bug-class lens each, and removes duplicate findings. Independent verifiers confirm or reject each finding. You can pass the findings you pick to `/bf:bug-fix` or `/bf:gh`. It only reviews and never edits code | You want a deep sweep for runtime bugs, not conventions, in a branch, a PR, a path, or the whole repo |
| `/bf:poc <idea>` | Workflow | Interview and brainstorm → coherence-checked brief → fast build under dev conventions → smoke run → code/brief sync check. It uses no git and logs every decision in a `BRIEF.md` ADR log | You want to prove an idea fast, and keep the decisions in case it becomes the real thing |
| `/bf:autopilot [skill] <args>` | Workflow | Runs a core bf workflow (feature, quick, micro, review, design) from start to end. It answers every decision the wrapped workflow would ask you. Setup collisions still ask you | You want to stay hands-off while the decide oracle makes every decision |
| `/bf:decide <question>` | Oracle | One decisive verdict with a rationale. It weighs the options, picks one, and cites evidence | You need a quick call on one thing and trust a single opinion |
| `/bf:discuss <question>` | Oracle | Open dialogue to explore a question before you commit to a direction | You are not ready to decide yet and want to think out loud first |
| `/bf:consilium <question>` | Oracle | 3-critic council: one critic answers, two challenge it from opposite angles, and the majority wins | The decision is high-stakes or contested, and one opinion is not enough |
| `/bf:design <idea>` | Utility | Shareable system-design doc with diagrams, made through interactive Q&A | You need a design artifact on its own, with no git or PR |
| `/bf:visualize <doc>` | Utility | Turns an arch-audit or design doc into an interactive LikeC4 drill-down (context → container → component, plus request-flow views) in one local HTML file | You want to explore a system's structure instead of reading about it |
| `/bf:adr-writer [title]` | Utility | Drafts a numbered ADR through interactive Q&A. The ADR cites only tracked source files | You need to record an architecture decision as a real project doc |
| `/bf:review [--focus <lens>] [PR# \| files]` | Utility | Code review against bf conventions and the complexity gate. `--focus`, or a request for one angle, runs only the checks of that lens | Before you merge, or any time you want a second reviewer |
| `/bf:coherence [scope]` | Utility | Checks whether a change left the code it touched coherent, against the breakage kinds in the guidelines | Right after you edit existing code. It is the fast counterpart to `/bf:review` |
| `/bf:walkthrough [scope]` | Utility | Guided read of a finished change. It tours the hunks that carried a decision, one at a time, and collects your comments | Right after a build, while you still remember why you did it that way |
| `/bf:arch-audit [scope]` | Utility | Descends a repo layer by layer, one round per build unit, and writes a nested document that describes every layer and its structural problems | You need to understand how an existing system is built, or where its bottlenecks are |
| `/bf:pr-comments [pr]` | Utility | Triages PR review feedback on its merits. For each comment, it fixes the whole class of problem the comment points at, argues back, or defers. It posts replies and resolutions as one approved batch | A PR has review comments from people or bots, and you want them judged rather than obeyed |
| `/bf:gh` | Utility | Creates, picks, or verifies a GitHub issue. Verify checks each item of an issue against the code again and hands off the items that are still open | You start work from an issue tracker, or want to check whether an old issue is still real |
| `/bf:jira` | Utility | Picks a Jira ticket and starts a workflow | You start work from Jira |
| `/bf:write-skill [name]` | Utility | Writes a new bf-style skill from scratch | You want to extend bf with a new skill |
| `/bf:onboard-skill <url> <instructions>` | Utility | Fetches an external skill, analyzes what to port, adapts it to bf conventions, and hands it to bf:write-skill | You want to take a skill from another plugin and adapt it for bf |
| `/bf:kit <purpose>` | Utility | Builds a standalone, git-initialized plugin, a "kit", for one domain. It interviews you for its main context, ingests your materials, agrees a skill roster with you, and drafts the skills you pick. It ships `write-skill`, `adopt-skill` and `update-context`, so the kit can grow on its own | You want a separate plugin for a course, a role, or a recurring kind of work (for example, a CTO-course kit) instead of more skills in bf |
| `/bf:self-audit [scope]` | Utility | Sweeps every skill, script, and convention for drift, stale references, and token waste, then files the findings as GitHub issues | You want to know what has decayed in the plugin itself. It pairs with `/bf:self-heal`, which fixes what it files |
| `/bf:self-heal [repo \| ids]` | Utility | Harvests the plugin's own open issues, scores them on token frugality, quality, and speed, argues for the top 3, fixes them, and ships one PR | The backlog has collected skill-improvement suggestions and you want the best three fixed in one pass |
| `/bf:scan-conventions [task]` | Utility | Discovers user-defined custom conventions and keeps the ones that apply to the current task | Before you act on a task where project or user convention files outside the predefined set might apply |
| `/bf:typesafe [status \| on \| off]` | Utility | Opt-in TypeSafe (System One / Jev) boosting. It checks your API key with a live smoke call, then sets one flag in `~/.bf/config.json` | You want typed model judgments in the places where bf now guesses with regex. It is optional, and bf behaves the same without it |
| `/bf:session-summary` | Utility | Summary of what happened this session | At the end of a work session, to record what changed and why |
| `/bf:gather <feature or PRD>` | Utility | Iterative requirements gathering and versioned PRD distillation across sessions | You have a vague PRD and must track open questions, scope a POC, and build a versioned source of truth |
| `/bf:research <topic>` | Utility | Decision-oriented researcher. It clarifies usecase → issue → focus, collects cited evidence, and writes an Options + Recommendation report | You need prior art, a library comparison, or decision support before you build, and want a cited report saved to `.bf/research/` |
| `/bf:essence [top N] <doc>` | Utility | One Essentialism pass over a finished research report, PRD or spec. It locks one essential intent with you, keeps at most N vital directions (default 3), and carries hard constraints through. It parks the rest with a reason, in a distilled copy | A doc has become noisy and you want only the directions that matter before you build from it |
| `/bf:plain <file \| text> [strict \| flavored]` | Utility | Rewrites existing prose into plain technical English (ASD-STE100) under the `prose` convention. It uses short active sentences and removes marketing words and em dashes. Code and identifiers stay untouched | A README, PR description, or error message reads like AI slop and you want it plain |
| `/bf:teach <topic>` | Utility | Stateful tutor across sessions: mission-based HTML lessons, reference docs, learning records, resources, and a glossary in a workspace per topic. An optional learning profile adapts how lessons are delivered | You want to study a topic over time rather than get a one-off explanation |
| `/bf:onboard-project-brief [path]` | Utility | One-page orientation to the repo in one cheap pass, with no questions. It covers what the repo does, its main blocks, stack, glossary, key commands, and where to look first, and writes to `.bf/onboard-brief/` | You want the gist of a project fast, before you decide whether you need the full course |
| `/bf:onboard-project [role or first task]` | Utility | Surveys the repo and generates a complete bf:teach onboarding course in one run. It covers purpose, domain, architecture, stack, running it locally, data, APIs, dependencies, config, testing, delivery, ops, workflow, and a first task | You just joined a project and want the whole codebase taught from start to end, then continued with `/bf:teach` |
| `/bf:session-lesson [optional focus]` | Utility | Mines this session for study topics, such as tech or your own repeated English mistakes, and writes one bf:teach lesson with a cheat sheet | At the end of a work session, to keep what it taught you |

## Workflow scenarios

The table above lists what each skill does on its own. In practice you chain them: the output of
one skill is the input of the next. Every arrow below is a real handoff. Each skill either offers the
next step, or writes an artifact that the next skill reads. You type each command. Nothing chains
silently.

### Ship a feature from a vague idea

```text
/bf:research <topic>       cited Options + Recommendation report in .bf/research/
/bf:consilium <question>   3-critic council settles the contested call the report surfaced
/bf:feature <idea>         brainstorm → spec → review-design → plan → [you approve] → execute
                           → verify → audit stack → review → commit, push, PR
/bf:walkthrough            tour the hunks that carried a decision, while you still remember why
```

Use `/bf:decide` instead of `/bf:consilium` when one opinion is enough. Skip research when you
already know the prior art.

### Align on requirements before anyone writes code

```text
/bf:gather <PRD or idea>   versioned requirements doc, open questions tracked across sessions
/bf:design <feature>       shareable system-design doc with diagrams (no git, no PR)
/bf:visualize <design-doc> optional: interactive drill-down to show the team
/bf:feature <feature>      builds from the settled docs instead of brainstorming from scratch
```

Choose this when other people must agree first, or when the idea spans more than one session. If you
only want to think out loud, use `/bf:discuss` and go straight to `/bf:feature`.

### Understand an unfamiliar codebase and draw it

```text
/bf:arch-audit [scope]     layer-by-layer document of every build unit, plus structural findings
/bf:visualize <audit-doc>  LikeC4 drill-down (context → container → component), one local HTML file
/bf:adr-writer <title>     record a decision the audit exposed, citing only tracked files
/bf:feature <finding>      act on the finding worth fixing first
```

arch-audit never edits code, so findings stay comparable. If the goal is to learn the repo rather than
judge it, use `/bf:onboard-project` instead.

### Join a new project (or onboard a teammate)

```text
/bf:onboard-project-brief [path]           step 0: a one-page brief, no questions
/bf:onboard-project <role or first task>   full course: domain, architecture, stack, run locally, ops…
/bf:teach <slug>                           continue the course: questions, deeper lessons, glossary
/bf:session-lesson                         after a real work session, turn what it taught into a lesson
```

Hand a teammate the generated workspace. `/bf:teach` picks up from there. For a single topic rather
than a whole repo, start with `/bf:teach <topic>`.

### Fix a regression

```text
/bf:bug-fix <symptoms>     parallel root-cause hunt → decide-gated fix → sibling sweep, no prompts
/bf:coherence              did the fix leave the code it touched coherent?
/bf:review                 full pre-merge review; then commit and open the PR yourself
```

bug-fix stops at a summary and does not commit. If you prefer to steer each phase and have the PR opened
for you, use `/bf:quick <fix>`.

### Work through PR review feedback

```text
/bf:review --focus security <PR#>   optional: your own focused pass before reviewers arrive
/bf:pr-comments <PR#>               judge every comment: fix the whole class, argue back, or defer.
                                    Contested ones escalate to the council. One approved batch.
/bf:gh                              file the deferred items as an issue so they aren't lost
```

Use this when comments come from people or bots and some of them are wrong. A blind fix of every
comment costs more than a triage.

### Prove an idea before committing to it

```text
/bf:poc <idea>             interview → brief → smallest working build → smoke run; no git
/bf:feature <BRIEF.md>     graduate it: the brief seeds the real feature
```

Choose this over `/bf:feature` when the question is "can this work at all?" rather than "how should
we build it?".

### Pick up a stale issue

```text
/bf:gh                     pick an issue, or verify one: re-checks each item against the code
                           → hands only the still-open items to /bf:quick or /bf:feature
/bf:walkthrough            read back what changed before you merge
```

Verify first when the issue is old, because some items are often already fixed. For a one-file
cleanup that does not need an issue, `/bf:micro <change>` runs refactor → guards → PR.

### Keep the plugin healthy

```text
/bf:session-summary        end of session; optionally files skill-improvement suggestions as an issue
/bf:self-audit             sweep skills, scripts and conventions for drift; file findings as issues
/bf:self-heal              score the backlog, argue for the top 3, fix them, ship one PR
```

Run self-audit on a schedule and self-heal whenever the backlog grows. Extending bf is a different
job: use `/bf:write-skill` or `/bf:onboard-skill <url>`.

### Build your own plugin for a domain

```text
/bf:kit <what it's for>          interview → your materials → skill roster → drafted skills, as a
                                 standalone, git-initialised plugin outside bf
/<kit>:update-context <change>   refine its context, or add notes, docs and URLs to its knowledge
/<kit>:write-skill               no argument: draft the next skill from the kit's BACKLOG.md
/<kit>:adopt-skill <url | path>  pull an existing skill into the kit and adapt it
```

Choose this when the skills serve a subject, such as a course, a role or a recurring kind of
work, rather than bf itself. Afterwards the kit grows on its own, so extend it with its own skills,
not with `/bf:kit`.

### Hands-off

Any of `feature`, `quick`, `micro`, `review` or `design` can run under `/bf:autopilot`, for example
`/bf:autopilot quick fix the flaky retry test`. The decide and consilium oracles answer every question the
workflow would ask you. You read the decisions in the session log afterwards.

## Getting started

### Add the marketplace

Register the `bf` marketplace with Claude Code (one-time setup):

```shell
/plugin marketplace add fxmaxvl/bf
```

### Install

```shell
/plugin install bf@fxmaxvl
```

Then run `/reload-plugins` to activate it.

### Stay up to date

**Turn on auto-update (recommended).** Claude Code refreshes marketplaces that have auto-update
enabled shortly after the first message of a session, and installs any new plugin version it finds.
Auto-update is off by default for third-party marketplaces like this one. No manifest field can
switch it on for you, so each user enables it once:

> `/plugin` → **Marketplaces** → select `fxmaxvl` → **Enable auto-update**

Administrators can set it for a whole fleet instead, with `"autoUpdate": true` on the
`extraKnownMarketplaces` entry in managed settings.

**Update by hand.** Without auto-update, pull new versions yourself:

```shell
/plugin marketplace update fxmaxvl      # refresh the catalog, in a session
claude plugin update bf@fxmaxvl         # update the plugin, from a shell
```

Claude Code installs a new copy only when the plugin version changes, so `bf` bumps `version` in
`.claude-plugin/plugin.json` on every release.

### Uninstall

```shell
/plugin uninstall bf@fxmaxvl
```

### Test locally without installing

```shell
claude --plugin-dir ./path/to/bf
```

## Conventions

The `conventions/` directory contains language- and action-specific guidelines Claude reads before acting:

- `guidelines.md`: behavioral guardrails. Unconditional, applies to every phase of every skill
- `prose.md`: plain technical English (ASD-STE100) for all prose bf writes for people. Unconditional. Excludes code and model-facing files
- `dev.md`: writing and modifying code
- `testing.md`: writing and modifying tests
- `git.md`: commit messages (Conventional Commits)
- `architecture.md`: architectural decisions
- `code-review.md`: reviewing code
- `typescript.md`: TypeScript/JavaScript specifics
- `python.md`: Python specifics
- `verification.md`: evidence rules the decide and discuss oracles run on

**Overriding conventions:** bf supports a 3-level lookup for each convention file. The first match wins and fully replaces the plugin default:

1. `<project_root>/.bf/conventions/<name>.md`: project-local override
2. `~/.bf/conventions/<name>.md`: user-global override
3. Plugin default (bundled in `conventions/`)

To override a convention, create the `.bf/conventions/` directory in the right location and add files with the same names as above (for example, `dev.md`, `git.md`). A matching file fully replaces the plugin default. There is no merging.

## Optional: TypeSafe boosting

**bf works fully without this.** You can skip the section and miss nothing. No skill requires it, no
prompt asks you about it, and every code path below runs the same deterministic logic as before.

A few places in bf must answer a question that regex handles badly. Today each one guesses with a
pattern or a hardcoded list, and each guess has a known failure:

- **`/bf:self-heal` reads a backlog issue as one lump** when the body uses neither `### ` headings
  nor `- **` bullets. Selection and scoring work per item, so an unsplit issue wins or loses as a
  whole. The issues that fail this way are the ones a person wrote, not the ones `/bf:self-audit` filed.
- **`/bf:self-audit` files false findings** from a word list (`path`, `to`, `foo`, `your`, …). The
  list decides whether `some-skill/SKILL.md` in a doc is a broken reference or just prose. The list
  can never be complete, and every false finding becomes a GitHub issue that self-heal then pays to
  reject.
- **A quality gate opens silently** when a report says `**STATUS:** BLOCK` instead of
  `STATUS: BLOCK`. The grep misses, and the caller gets `NOT_FOUND`. A missing report also
  returns `NOT_FOUND`, so nothing tells "clean" apart from "never ran".
- **`/bf:autopilot fix the login bug` runs the full feature workflow**, brainstorm included, because
  only an exact first word routes anywhere else.
- **`/bf:research` asks what your prompt already said.** It also grades its own citations
  `direct`/`doc`/`inference`, and nothing checks the tag against the quote.

Connecting [TypeSafe](https://docs.typesafe.ai) replaces those guesses with typed judgments:
yes/no probabilities and single-choice picks, not generated text. The shape is always the same:
**code lists the candidates, the model picks among them, and code slices the original text**. A
boosted run can pick wrong, but it can never invent content that was not in the source.

```bash
export TYPESAFE_API_KEY=...   # in your shell profile
/bf:typesafe on               # smoke-calls the API, then flips one flag
/bf:typesafe off              # back to deterministic, any time
```

`on` writes `typesafe.enabled` to `~/.bf/config.json` **only if the smoke call answers**. A
mistyped key therefore fails loudly at setup instead of silently degrading every later run. bf never
writes the key itself to disk, only the name of the env var that holds it.

When boosting is off, unconfigured, rate-limited, or the API is unreachable, every call site falls
back to the deterministic path and the run continues. This is a design rule: a boost that breaks
when removed is a dependency, and it does not ship. See
[`docs/typesafe-opportunities.md`](docs/typesafe-opportunities.md) for the call sites and the ones
still on the list.

## Requirements

- [Claude Code](https://claude.ai/code)
- `gh` CLI (for `/bf:gh` and PR creation)
- Jira MCP server configured (for `/bf:jira`)
- Excalidraw MCP server (optional, for diagrams in `/bf:design`)
- TypeSafe API key (optional, see [TypeSafe boosting](#optional-typesafe-boosting))
