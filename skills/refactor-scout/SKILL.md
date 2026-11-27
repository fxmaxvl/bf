---
name: refactor-scout
description: "Use when the user has no task yet and wants to measure a repo or module for refactoring candidates — 'find refactoring candidates', 'what should we refactor in src/billing', 'measure this module', 'scan for duplicate code', 'where is the complexity'. Runs crapper and dryer (mutator with --mutate), groups candidates by metric, ranks each group by score × git churn, then plans one candidate with a measurable definition of done and re-checks it after the refactor. Report-only: it hands the refactor to bf:micro or bf:feature. For a diff or PR use bf:review, for structure use bf:arch-audit."
model: opus
disable-model-invocation: false
argument-hint: "[scan] [--only crapper|dryer] [--mutate] [path...] | plan <id> | check <id>"
allowed-tools: Read, Write, Grep, Glob, Skill, Bash(git *), Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill, including **one-question-per-turn**.

You measure, rank and plan. You never edit source code. The refactor runs in `/bf:micro` or `/bf:feature`, and this skill checks the result.

## On Invocation

Print banner (plain text):

```
── bf:refactor-scout ───────────────────────────────────
```

Pick the mode from the first word of the argument:

| First word | Mode |
|---|---|
| `plan` | Plan, with the next word as the candidate id |
| `check` | Check, with the next word as the candidate id |
| `scan`, a flag, a path, or nothing | Scan |

A candidate id is `C3`, `D1` or `M2`, or `<run>/<id>` for a run other than the latest one.

Every call to `scout.sh scan` and `scout.sh check` passes `timeout: 600000` on the Bash call. The script stops its tools at 480 s and churn after another 45 s (`SCOUT_BUDGET_S` and `CHURN_S` in `scout.py`), so keep the two in step.

## Scan

1. Restate the effect in one line before the run: the tools write `.metrics`, `target` and `coverage` at the repository root while they run, and remove the ones they created. The report goes to `.bf/refactor-scout/<run>/`. With `--mutate`, also say that mutator runs the test suite once per mutant and can take up to 8 minutes.
2. Write the scope paths with the Write tool to `<working directory>/.bf/tmp/refactor-scout-args.txt`, one path per line, exactly as the user gave them. Write an empty file when no path was given. That means the whole repository. Flags (`--only crapper`, `--only dryer`, `--mutate`) stay on the command line:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/refactor-scout/scripts/scout.sh" scan <flags> < "<working directory>/.bf/tmp/refactor-scout-args.txt"
   ```

3. On `{"applicable": false}`, print the `reason` and stop. It names the tool that is missing or the languages the scope holds instead, for example a Scala service. Do not fall back to judging the code by reading it.
4. On `{"applicable": true}`, read the `report` file. Print, in this order:
   - Each line of its `## Measured` section, so the skipped share is visible.
   - Each group's active candidates (at most 5), with the table header. Name how many stable candidates the report holds, and do not list them.
   - The report path, and this line: `Next: /bf:refactor-scout plan <id> for one candidate.`

## Plan

1. Load the candidate:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/refactor-scout/scripts/scout.sh" show <id>
   ```

   It returns `{run, head, candidate}`. The candidate has `group` (`dryer`, `crapper` or `mutator`), `done_when`, `score`, `churn`, and its files and functions.
2. Create `<repo root>/.bf/refactor-scout/<run>/<id>-plan.md` with the Write tool. It starts with `# Plan: <id>`, then a `## Candidate` block that holds the candidate JSON and the `done_when` line. The rest of this mode appends to that file.
3. **Find the similar cases.** One refactor should cover every copy of the problem.
   - `dryer`: the members are the cases. Read each member's span.
   - `crapper`: read the function. Grep the scope for functions that call the same helpers or follow the same shape. Add other `crapper` candidates from the same directory in `<run>/candidates.json`.
   - `mutator`: read the function and the tests that reach it.

   Append a `## Similar cases` block: one line per case, with `file:line` and what it shares.
4. **Design 2 or 3 options**, each aimed at the candidate's own metric. A DRY option reduces duplicate pairs and does not lower CC as a side goal. Append a `## Options` block. For each option give:
   - what changes, and in which files
   - the expected result against `done_when` (for example "the 7 pairs go to 0")
   - the risk, including callers and public interfaces it touches
   - the size: **micro** when it stays within 3 files and changes no public interface, **feature** otherwise

   Two rules for the options:
   - **Leave it as it is** is always a valid option. Duplication that an interface requires (every stub of a port answers each method) or a split that only spreads the branches around is not worth a refactor. When it wins, the hand-off records the candidate as accepted, with the reason.
   - **Reject an option that only moves the number.** Deleting comments to push a form under dryer's 4-line minimum, renaming to break name matching, or splitting a function into pieces that each still need the others all meet `done_when` and improve nothing. Each option says what gets easier to change, not only which score drops.
5. **Challenge the options.** Invoke `Skill("bf:consilium")` with this payload:

   ```
   QUESTION: Which option meets "<done_when>" for <id> with the least risk, or is leaving it as it is the better call?
   PHASE: refactor-scout plan
   SESSION_LOG: <absolute path of the plan file>
   OPTIONS: A) <option A> | B) <option B> | C) <option C>
   CONTEXT:
   <the Candidate, Similar cases and Options blocks>
   ```

6. **Write the hand-off.** Append a `## Hand-off` block with the chosen option. When the choice is to leave it as it is, write the reason and stop: there is no command. Otherwise give one command:
   - `/bf:micro <task>` or `/bf:feature <task>`, from the option's size.
   - The task text names the files, the change, and the definition of done word for word. It ends with: `When done, run /bf:refactor-scout check <run>/<id>.`

   Print the command and the plan path. Do not run the command. The user starts it.

## Check

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/refactor-scout/scripts/scout.sh" check <id> < /dev/null
```

It re-runs the candidate's tool on the candidate's files and on every file changed since the scan commit, including untracked files. It reuses the coverage mode of the scan, and it logs each result to `<run>/checks.jsonl`. It returns `{run, id, verdict, done_when, before, after, details, touched, notes}`.

Print the run it resolved, the verdict, and before → after. On `FAIL`, list what is left:
- `dryer`: the `details.remaining` pairs, then the `details.new` pairs.
- `crapper`: `after.new_over_limit`, and whether the target is still over the limit.
- `mutator`: the surviving count.

Print every note, in particular a tool version change since the scan. On `UNKNOWN`, print `details.reason`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `scout.sh` returns `{error, detail}` | Print the detail and stop. `no_runs` and `unknown_id` mean a scan is needed first, or the id is from another run: say to use `<run>/<id>`. |
| `tool_missing` on check | Print it with the `/bf:setup` hint. Do not re-check by reading the code. |
| Shallow clone note | Print it above the candidates: churn is low, and more candidates read as stable than really are. |
| A tool hit its time limit | Print the note. The candidates from the files measured before the limit are still valid. Suggest a narrower path. |
| The user asks to apply the refactor here | This skill never edits code. Give the hand-off command from the plan instead, or run plan first. |
| `plan` for a stable candidate | Say it has not changed in the 6 months before the last commit and ask one question: plan it anyway, or pick an active one. |
| The candidate's file no longer exists at plan time | Say the scan is out of date and suggest a new scan. |
| Called with a diff, branch or PR | Point to `/bf:review --focus complexity`, which measures a change, not a module. |
