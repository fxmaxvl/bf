---
name: teach
description: "Use when the user wants to deliberately learn a topic over multiple sessions — 'teach me X', 'tutor me on X', 'I want to learn X'. Maintains a stateful per-topic teaching workspace with mission-grounded lessons, reference docs, learning records, resources, and a glossary. Not for one-off explanations."
model: sonnet
# Lesson/reference generation is high-volume content work Sonnet handles well; ZPD calc
# and the mission interview are low-token, interactive — not enough to justify opus.
# Bumping to opus is defensible if pedagogical quality proves lacking.
disable-model-invocation: true
# DELIBERATE: preserves the source skill's command-only intent. A loose phrase must NOT
# auto-spin a multi-session workspace — this fires only on explicit /bf:teach.
argument-hint: "What would you like to learn about?"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Teach the user a topic over multiple sessions, grounding every lesson in their real-world mission and building knowledge → skills → wisdom that sticks.

## On Invocation

Print banner (plain text, not a code block):

```
── bf:teach ─────────────────────────────────────────────
```

Parse the topic from the argument. If no topic is given, ask ONE question: what they want to learn. This is a **stateful, multi-session** request — the user intends to learn this topic over time, not in one sitting.

### Workspace location (deviates from plugin-main, by design)

Teaching content is **personal and cross-project**, so the workspace is **always user-global** — never the project-first `.bf/` lookup. Putting HTML lessons and learning material into a work repo's `.bf/` would scatter personal study material across codebases.

- Workspace root: **`~/.bf/teach/<topic-slug>/`** — always, regardless of cwd or git repo.
- This skill also does **not** use plugin-main's session-log/temp two-file layout (that pattern is for one-shot workflow skills). Each topic gets its own persistent directory instead.

Workspace layout inside `~/.bf/teach/<slug>/`:

| Path | Purpose |
|------|---------|
| `MISSION.md` | Why the user is learning this — grounds every decision. See [./MISSION-FORMAT.md](./MISSION-FORMAT.md). |
| `RESOURCES.md` | Curated high-trust sources + communities. See [./RESOURCES-FORMAT.md](./RESOURCES-FORMAT.md). |
| `GLOSSARY.md` | Canonical, opinionated terminology. See [./GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md). |
| `NOTES.md` | Scratchpad for stated teaching preferences. |
| `lessons/NNNN-<slug>.html` | The primary teaching unit — one self-contained lesson. |
| `reference/NNNN-<slug>.html` | Compressed reusable knowledge, designed for quick review. |
| `learning-records/NNNN-<slug>.md` | ADR-style insights that steer future sessions. See [./LEARNING-RECORD-FORMAT.md](./LEARNING-RECORD-FORMAT.md). |

## Philosophy

To learn at a deep level the user needs three things:

- **Knowledge** — captured from high-trust resources, **never** parametric guesses.
- **Skills** — acquired through interactive lessons with tight feedback loops.
- **Wisdom** — earned by testing skills in real-world community interaction.

Some topics lean knowledge-heavy (theoretical physics), others skills-heavy (yoga). Weight your effort accordingly.

**Fluency vs storage strength.** *Fluency strength* is in-the-moment retrieval — it gives an illusory sense of mastery. *Storage strength* (long-term retention) is the real goal. Build it through **desirable difficulty**: retrieval practice (recall from memory), spacing (distribute practice over time), and interleaving (mix related topics — skills practice only).

The split that governs lesson design:

- **Knowledge acquisition: difficulty is the enemy.** It eats the working memory needed for understanding. Teach plainly.
- **Skill acquisition: difficulty is the tool.** Effortful retrieval is what builds storage strength. Make them work.

## Phase 1 — Locate / resume workspace

`mkdir -p ~/.bf/teach` and `ls` the existing workspace directories. Slugify the requested topic (lowercase, dash-separated).

Slugs are **lossy** — "learn Rust" and "Rust programming" produce different slugs but mean the same thing. Fuzzy-match the requested topic against existing workspace names. If a plausible match exists, ask ONE question: confirm whether to resume that workspace before creating a new one. Only create `~/.bf/teach/<slug>/` when there is no match (or the user declines it).

## Phase 2 — Ground in the mission

Read `MISSION.md`. If it is absent or vague, interview the user — **ONE QUESTION AT A TIME** (plugin-main hard rule; do not batch the interview). Then write `MISSION.md` per [./MISSION-FORMAT.md](./MISSION-FORMAT.md).

A bad mission is worse than no mission — push back on vagueness. Without a grounded mission, knowledge acquisition is unanchored, lessons feel abstract, and you cannot judge what to teach next.

Missions change as understanding grows. **Confirm with the user before changing an existing mission.** On change, update `MISSION.md` *and* add a cross-linked learning record (Phase 8).

## Phase 3 — Compute the zone of proximal development (ZPD)

Each lesson should challenge the user *just enough*. Unless they named an exact target, read `learning-records/` and `MISSION.md` to pick the most relevant next thing that sits inside their ZPD.

## Phase 4 — Gather knowledge

Before `RESOURCES.md` is well-populated, your priority is finding high-trust sources via WebSearch/WebFetch. **Never trust parametric knowledge.** Record sources in `RESOURCES.md` per [./RESOURCES-FORMAT.md](./RESOURCES-FORMAT.md) — grouped Knowledge / Wisdom, every entry annotated with what it covers and when to reach for it.

## Phase 5 — Produce the lesson (the primary output)

A lesson is the main thing you produce — the unit in which knowledge and skills reach the user. Write **one self-contained HTML file** to `lessons/NNNN-<slug>.html` (scan the directory for the highest number and increment).

- **Beautiful.** Clean, readable Tufte-style typography and layout — the user returns to these to review, and they should print well.
- **Short and quickly completable.** Working memory is small; stay within it. But each lesson must deliver one tangible win, tied to the mission and inside the ZPD.
- **Knowledge first, heavily cited.** Teach only the knowledge the skill requires. Link every claim to a `RESOURCES.md` source — citations build trust.
- **Then skill practice via a tight feedback loop.** Make the loop as immediate (ideally automatic) as possible: in-browser quizzes / light tasks, or a guided list of real-world steps (e.g. yoga poses).
- **No formatting tells.** Quiz answers must all be the same number of words (and characters where possible) — leak no clue about the right answer.
- **Cross-link.** Use HTML anchors to link to other lessons and reference docs.
- **One primary source.** Recommend the single highest-quality resource you found for this topic.
- **Teacher reminder.** Include a note that the user can ask the agent — their teacher — followup questions on anything unclear.
- Offer to open the lesson for the user with a CLI command (e.g. `open <file>` on darwin).

**Code-topic hook:** when the topic is programming, any code shown in lessons must honor the relevant conventions (`dev`, `typescript`, `python`) via plugin-main's 3-step convention lookup.

## Phase 6 — Reference + glossary upkeep

Extract reusable knowledge — syntax, algorithms, flowcharts, pose sequences, glossaries — into `reference/NNNN-<slug>.html`. References are the compressed essence of lessons, designed for quick review; unlike lessons, they *will* be revisited.

Promote terms into `GLOSSARY.md` per [./GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md) **only after the user demonstrably understands them** — compressing a concept into a tight definition is itself evidence of learning. Be opinionated; once a term is in the glossary, adhere to it everywhere.

## Phase 7 — Acquiring wisdom

Wisdom comes from real-world interaction. When a question needs real-world judgment, attempt an answer, then delegate to a high-reputation **community** — a forum, subreddit, real-world class (budget permitting), or local interest group. Respect opt-outs and record the user's community preferences in `RESOURCES.md`.

## Phase 8 — Record learning

Write a `learning-records/NNNN-<slug>.md` per [./LEARNING-RECORD-FORMAT.md](./LEARNING-RECORD-FORMAT.md) when ANY of these is true:

1. The user demonstrated genuine, non-trivial understanding (evidence of correct use, not mere exposure).
2. The user disclosed prior knowledge ("I already know X") — record it and the depth claimed.
3. A misconception was corrected — high-value, predicts future stumbling blocks.
4. The mission shifted — cross-link to `MISSION.md` and update it.

Do **not** write records for merely-covered material or session activity logs. Handle supersession by marking the old record `Status: superseded by LR-NNNN` rather than deleting it. Capture stated teaching preferences in `NOTES.md`.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| No topic given | Ask one question: what they want to learn. |
| Mission vague or absent | Interview one question at a time before writing `MISSION.md`. A bad mission is worse than none. |
| Plausible existing workspace for the topic | Ask one question to confirm, then resume — don't restart or duplicate. |
| Slug collision (two distinct topics slugify the same) | Disambiguate with the user (one question); suffix the slug. |
| User opts out of communities | Record in `RESOURCES.md`; stop proposing them. |
| Mission shift mid-topic | Confirm with the user, update `MISSION.md`, write a cross-linked learning record. |
| Code topic | Lessons honor `dev`/`typescript`/`python` conventions via the 3-step lookup. |
