# Complexity Taxonomy

Source: *A Philosophy of Software Design* by John Ousterhout.

Complexity is anything that makes a system harder to understand and modify.
It accumulates from two root causes and manifests as three observable symptoms.

---

## Root Causes

### 1. Dependencies
Code that cannot be understood or modified in isolation.

| Red Flag | How to detect | Fix |
|----------|--------------|-----|
| **Information leakage** | A design decision (e.g., data format, storage layout) is reflected in two or more modules that must change together | Consolidate behind a single module using information hiding |
| **Temporal coupling** | Module A must be called or initialized before module B, with nothing enforcing the order | Make ordering explicit via return value that carries required state, or eliminate the ordering requirement |
| **Pass-through methods** | A method does nothing except forward its arguments to another method with a similar signature | Eliminate the intermediary or deepen the abstraction |
| **Change amplification** | A single logical change requires edits in 5+ unrelated files | Extract a shared abstraction; consolidate the scattered decision into one place |
| **Conjoined methods** | Two methods only work correctly when called in a specific sequence or share hidden mutable state | Merge them or make the dependency explicit in the interface |
| **Shallow modules** | A module's interface is nearly as complex as its implementation — it adds little abstraction | Merge into the caller, or deepen it by pulling more implementation detail behind the interface |

### 2. Obscurity
Important information is not obvious.

| Red Flag | How to detect | Fix |
|----------|--------------|-----|
| **Non-obvious side effects** | A method modifies state beyond what its name or signature implies | Rename to reflect behavior; extract the side effect to a separate, clearly-named method |
| **Implicit preconditions** | A function silently misbehaves with certain inputs, with no enforcement or documentation | Validate at the boundary; document the precondition in a comment explaining why it exists |
| **Inconsistency** | The same concept has different names, formats, or representations in different parts of the codebase | Standardize — pick one name/shape and apply it everywhere |
| **Missing non-obvious comments** | A constraint, invariant, or workaround is present in the code but unexplained | Add a comment explaining WHY — not what the code does, but why it must be this way |
| **Special-case proliferation** | Multiple `if/else` or `switch` branches handle edge cases that could be expressed as a uniform rule | Define the general rule; absorb edge cases into it or push them to the boundary |

---

## Symptoms

Symptoms are the observable effects of complexity. Use them as diagnostic signals when scanning.

### 1. Change amplification
**Signal:** A seemingly simple change requires modifying many unrelated files or locations.
**Threshold:** 5+ file edits for a single logical change.
**Root cause:** Dependencies — information leakage or missing abstraction.

### 2. Cognitive load
**Signal:** A developer must hold a large amount of context in their head to understand or safely use a module.
**Indicators:** wide interfaces with many parameters, global or shared mutable state, methods that do more than their name implies, long parameter lists, implicit caller obligations.
**Root cause:** Dependencies and obscurity combined.

### 3. Unknown unknowns
**Signal:** It is not obvious what code needs to change to complete a task, or what information is required to make a change safely.
**Indicators:** behavior only discoverable by reading implementation (not interface), silent side effects, configuration scattered across files.
**Root cause:** Obscurity — implicit preconditions, non-obvious side effects, information leakage.

---

## Module Depth Reference

A **deep module** has a simple interface that hides significant implementation — this is the goal.
A **shallow module** has an interface nearly as complex as its implementation — this is a red flag (see Dependencies table above).

Detecting shallow modules:
- The public API surface is nearly as large as the implementation
- The module does little more than delegate to another module
- Removing the module would barely change any caller
