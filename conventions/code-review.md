# Code Review Conventions

When reviewing code, you MUST check compliance with the relevant convention docs. Do not infer conventions from the code itself — always read the docs.

Review the **full context** of changed code — not just the diff. Read the surrounding file, related modules, and how the change fits into the existing structure before forming conclusions.

---

## 1. Development conventions check

Read `./dev.md` and verify the changes comply with every rule. Key things to flag:

- Code style, naming, and patterns inconsistent with the existing codebase
- Changes larger in scope than the task requires (unrelated modifications)
- Removed or altered comments without justification
- Reimplemented or rewritten code where an update would have sufficed
- Names like `improved`, `new`, `enhanced`, etc.
- Any use of mock implementations

---

## 2. Testing conventions check

Read `./testing.md` and verify the changes comply with every rule. Key things to flag:

- Missing tests for the implemented functionality
- Missing unit, integration, or end-to-end tests (all three are required — no exceptions)
- Tests written after the implementation instead of before (TDD violation)
- Test output that is not pristine (unexpected logs, warnings, or errors not explicitly asserted)
- Tests that ignore or swallow logs/error output instead of asserting on them

---

## 3. Security check

Apply secure coding principles. Flag any of the following:

- **Injection**: unsanitized user input passed to SQL, shell, eval, or template engines
- **Broken auth**: credentials hardcoded, tokens stored insecurely, weak or missing auth checks
- **Sensitive data exposure**: secrets, PII, or tokens logged, serialized to disk, or returned in responses
- **Insecure deserialization**: untrusted data deserialized without validation
- **Missing input validation**: no bounds checks, type checks, or schema validation on external input
- **Improper error handling**: stack traces or internal details leaked in error messages
- **Dependency risk**: new dependencies added without vetting; known-vulnerable packages
- **Least privilege violations**: code requesting or using more permissions/access than the task requires
- **OWASP Top 10**: check changes against the full OWASP Top 10 where applicable

---

## 4. Code structure and fit check

Read the surrounding code — the file, the module, and related components — before evaluating fit. Flag:

- Logic placed in the wrong layer or abstraction level (e.g., business logic leaking into UI or data layer)
- New code that duplicates something that already exists elsewhere in the codebase
- Inconsistency with the architectural patterns already in use (read `./architecture.md`)
- Abstractions introduced prematurely for a single use case (YAGNI)
- Missing abstractions where similar logic appears more than twice (DRY)
- Classes, modules, or functions doing more than one thing (SRP violation)

---

## 5. Readability and code quality (Code Complete principles)

Apply insights from *Code Complete* (McConnell) when evaluating quality:

**Naming**
- Names should fully and accurately describe what the variable, function, or class does — no abbreviations, no single-letter variables outside tight loops
- Boolean names should imply true/false (e.g., `isReady`, `hasPermission`)
- Routine names should describe the return value or the action performed, not the implementation

**Routine design**
- Each routine should do one thing and do it well; if you need "and" to describe it, it does too much
- Routines longer than ~200 lines are a smell — flag for review
- Deep nesting (more than 3 levels) hurts readability; suggest guard clauses or extraction

**Variables and data**
- Variables should be used for one purpose only; dual-purpose variables are confusing
- Magic numbers and magic strings must be named constants
- Minimize variable scope — declare as close to first use as possible

**Complexity**
- Cyclomatic complexity above ~10 in a single routine is a flag — suggest decomposition
- Complex boolean expressions should be extracted into named predicates
- Prefer straightforward control flow over clever short-circuits when readability suffers

**Comments**
- Comments should explain *why*, not *what* — if the comment restates the code, it adds no value
- Comments must stay in sync with the code; outdated comments are worse than none

**Simplification recommendations**
- If a simpler solution exists — in implementation, abstraction design, or class hierarchy — **always recommend it**, even if the current solution is technically correct
- Prefer flat structures over deep hierarchies when the added levels carry no semantic value
- Prefer composition over inheritance when inheritance would create tight coupling or fragile base class problems
- If a class hierarchy can be replaced by a simple strategy or function, say so

---

## How to report findings

Group findings by section. For each issue:
1. State the problem clearly
2. Cite the specific file and line if possible
3. Explain why it matters
4. Suggest a concrete fix or improvement

Distinguish between **must fix** (correctness, security, convention violations) and **should consider** (quality, simplification, readability).
