---
name: complexity-gate
description: Scan for complexity red flags (per A Philosophy of Software Design), classify findings as session-introduced vs pre-existing, and produce a structured fix plan.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git *)
model: opus
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill.

Read `${CLAUDE_PLUGIN_ROOT}/skills/feature/complexity-gate/COMPLEXITY.md` — this defines the taxonomy, red flags, and fix prescriptions you will apply.

## Mode Detection

Run state-ops.sh to load session context:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/state-ops.sh"
```

Use the `phase` field to determine the mode:

| Phase | Mode | Input |
|-------|------|-------|
| `review-design` | Spec advisory | `paths.spec` |
| `plan` | Plan advisory | `paths.plan` |
| `verify` | Scan | `changed_files` from `changed-packages.sh` |

For scan mode also run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/feature/scripts/changed-packages.sh"
```

---

## Spec Advisory Mode (`phase = review-design`)

Extract the `## Spec` block from `paths.spec` (= `paths.session_log`) using the Block Reading Pattern from `plugin-main.md`. Apply the complexity taxonomy as a design lens — evaluating proposed design decisions before any code is written.

Look for:
- Module boundaries that will cause **information leakage** (two modules share knowledge of a data format or storage structure)
- API shapes that are **shallow** (interface nearly as complex as the proposed implementation)
- Interactions implying **temporal coupling** (caller must perform steps in a specific order)
- Responsibilities spread across modules causing **change amplification** (one logical change touches many places)
- Concepts named or represented differently across the design (**inconsistency**)

For each finding, cite the spec section and explain the complexity risk it introduces.

All findings in this mode are `ADVISORY`. STATUS is `ADVISORY` or `PASS`.

Append the report to `paths.complexity_report` (= `paths.temp`) using `paths.block_complexity_report` (`## Complexity Report`) as the block header (Block Writing Pattern from `plugin-main.md`). Display the report in the conversation.

---

## Plan Advisory Mode (`phase = plan`)

Extract the `## Plan` block from `paths.plan` (= `paths.session_log`) using the Block Reading Pattern from `plugin-main.md`. Apply the complexity taxonomy as an implementation lens — evaluating planned structure before any code is written.

Look for:
- Implementation steps that both touch the same data structure or format (information leakage risk)
- Steps that must complete in a specific order with no enforcement mechanism (temporal coupling risk)
- Planned modules whose proposed interface is as wide as their implementation (shallow module risk)
- The same logic appearing in multiple steps with no shared abstraction (change amplification risk)
- Methods described as doing more than one thing (cognitive load / non-obvious side effects risk)

For each finding, cite the step or plan section and explain the complexity risk.

All findings in this mode are `ADVISORY`. STATUS is `ADVISORY` or `PASS`.

Append the report to `paths.complexity_report` (= `paths.temp`) using `paths.block_complexity_report` (`## Complexity Report`) as the block header (Block Writing Pattern from `plugin-main.md`). Display the report in the conversation.

---

## Scan Mode (`phase = verify`)

Scan `changed_files` for concrete complexity red flags in the actual code.

For each red flag in COMPLEXITY.md, scan using Grep and Read. For each finding, record:
- File path and line number
- Which red flag it matches (exact name from COMPLEXITY.md)
- Which root cause and symptom it maps to
- Whether the file is in `changed_files` (determines severity)
- The prescribed fix from COMPLEXITY.md

### What to look for

Focus on structural signals, not style preferences:

- Methods/functions that do more than their name implies (non-obvious side effects)
- Modules whose public interface is nearly as large as their implementation (shallow modules)
- Logic duplicated across multiple files with no shared abstraction (change amplification risk)
- Caller obligations not enforced or documented (implicit preconditions, temporal coupling)
- The same concept represented differently in different parts of the codebase (inconsistency)
- Methods that only forward arguments to another method (pass-through methods)
- Chains of `if/else` or `switch` for cases expressible as a uniform rule (special-case proliferation)

### Severity

- **BLOCK** — red flag in a file listed in `changed_files`. New complexity introduced this session.
- **ADVISORY** — red flag in a file outside `changed_files`.
- **PASS** — no red flags found.

Overall STATUS escalates: `PASS` → `ADVISORY` → `BLOCK`.

Append the report to `paths.complexity_report` (= `paths.temp`) using `paths.block_complexity_report` (`## Complexity Report`) as the block header (Block Writing Pattern from `plugin-main.md`). Display the report in the conversation.

---

## Report Format

No findings:

```markdown
## Complexity Report

STATUS: PASS
```

Findings present:

```markdown
## Complexity Report

STATUS: BLOCK | ADVISORY

## Blocked Issues (introduced this session — must resolve before proceeding)

### <Root Cause> / <Symptom> — <Red Flag Name>
- `<file>:<line>` — <what was observed> — **Fix:** <prescription from COMPLEXITY.md>

## Advisory Issues (pre-existing or design risk)

### <Root Cause> / <Symptom> — <Red Flag Name>
- `<file>:<line or spec section>` — <what was observed> — **Suggestion:** <prescription from COMPLEXITY.md>
```

Omit sections that have no entries.

Do **not** modify any files. Do **not** ask the user questions. The caller handles gate logic.
