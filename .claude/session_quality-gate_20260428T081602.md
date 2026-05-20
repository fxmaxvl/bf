# Session Summary — quality-gate sub-skill promotion
**Date:** 2026-04-28  
**Slug:** quality-gate  
**Turns:** ~12

---

## What we did

Promoted `quality-gates` from a user-overridable convention to a proper internal sub-skill (`quality-gate`) — following the same pattern as `complexity-gate`.

### Changes shipped (commit `b42fb7e`)
- **Created** `skills/bfeature/quality-gate/SKILL.md` — phase-aware sub-skill: writes the Quality Gates section to the plan file during `plan` phase; outputs resolved commands to context during `verify` phase
- **Deleted** `conventions/quality-gates.md`
- **`conventions/plugin-main.md`** — removed the `quality-gates` row from the override lookup table
- **`plan/SKILL.md`** — replaced convention lookup with direct sub-skill read
- **`verify/SKILL.md`** — same
- **`skills/bfeature/SKILL.md`** — added `quality-gate` to the phase sub-skills table (`Inline | sonnet`)

---

## Key decisions made

| Decision | Rationale |
|----------|-----------|
| Sub-skill, not just a moved doc | Maks explicitly wanted parity with `complexity-gate` — own SKILL.md, own frontmatter, own model routing |
| Inline invocation (not Agent prompt) | `verify` needs resolved commands in its execution context after quality-gate runs; a separate Agent context would require a state-file roundtrip for simple command resolution |
| Phase-aware (plan vs verify) | Mirrors how `complexity-gate` uses `phase` from state-ops.sh to switch modes — same pattern, consistent mental model |
| Renamed to singular `quality-gate` | Consistency with `complexity-gate` naming convention |
| Removed from convention lookup | The whole point — users can no longer override it and silently break plan/verify command resolution |

---

## Efficiency insights

- Discussion phase caught the key design fork early (sub-skill vs. plain internal doc, Agent vs. inline invocation) — avoided a wrong implementation.
- The "like complexity-gate" answer collapsed several open questions at once (structure, location, frontmatter pattern).
- Post-commit scan confirmed zero stale references — no cleanup needed after the fact.

---

## Process observations

- The `discuss` skill worked well here: surfacing the inline vs. Agent invocation tradeoff before implementation saved a round of rework.
- One subtle asymmetry worth noting: `complexity-gate` is invoked as an Agent (separate context) by the orchestrator; `quality-gate` is invoked inline by plan/verify. They look similar in the sub-skills table but have different invocation semantics — worth documenting more explicitly in SKILL.md at some point.

---

## Possible improvements

- The sub-skills table in `SKILL.md` has an `Invocation` column (`Agent` vs `Inline`) but no explanation of what that difference means for callers — a one-line note would help future contributors.
- `quality-gate` re-runs `detect-stack.sh` even when the calling skill (plan/verify) already ran it. Harmless but redundant — could be noted as a known tradeoff of the inline sub-skill pattern.
