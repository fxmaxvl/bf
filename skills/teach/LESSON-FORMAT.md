# Lesson & Reference Format

Lessons live in `lessons/NNNN-<lesson-slug>.html` and references in `reference/NNNN-<reference-slug>.html` under the teaching workspace (`~/.bf/teach/<slug>/`). `<slug>` always names the workspace; `<lesson-slug>` names what one lesson covers; `<reference-slug>` names what one reference covers, which may be an area several lessons feed. A lesson is the main thing `bf:teach` produces — the unit in which knowledge and skills reach the user. A reference is the compressed essence of lessons, built for quick review.

## Numbering

- `lessons/` and `reference/` are numbered independently: `NNNN` = highest existing + 1, starting at `0001`.
- Immediately before writing, check the path doesn't exist; if it does, take the next number. Never overwrite.
- `0000-*` files (e.g. an onboarding course map) are not lessons; exclude them from lesson counts.
- `<lesson-slug>` and `<reference-slug>` name what the file covers, never the workspace, so other skills can read covered material from filenames.
- Courses with a fixed syllabus (`bf:onboard-project`) use its assigned numbers instead of scanning.

## Lesson

Write **one self-contained HTML file** per lesson, numbered per [Numbering](#numbering).

- **Beautiful.** Clean, readable Tufte-style typography and layout — the user returns to these to review, and they should print well.
- **Short and quickly completable.** Working memory is small; stay within it. But each lesson must deliver one tangible win, tied to the mission and inside the ZPD.
- **Knowledge first, heavily cited.** Teach only the knowledge the skill requires. Link every claim to a `RESOURCES.md` source — citations build trust.
- **Then skill practice via a tight feedback loop.** Make the loop as immediate (ideally automatic) as possible: in-browser quizzes / light tasks, or a guided list of real-world steps (e.g. yoga poses).
- **No formatting tells.** Quiz answers must all be the same number of words (and characters where possible) — leak no clue about the right answer.
- **Cross-link.** Use HTML anchors to link to other lessons and reference docs.
- **One primary source.** Recommend the single highest-quality resource you found for this topic.
- **Teacher reminder.** Include a note that the user can ask the agent — their teacher — followup questions on anything unclear.
- **Honor the learning profile.** If a `Status: active` profile was loaded, shape the lesson to it — theory-first vs example-first, density and pacing, preferred modality (diagrams / prose / code / analogies / checklists), and feedback/practice style — and avoid what the profile lists as dislikes. The profile tunes *delivery*; it never overrides the knowledge-first / desirable-difficulty principles above. If no profile is loaded (absent or declined), use the default lesson design.
- **Offer to open the lesson** with a CLI command (e.g. `open <file>` on darwin).

**Code-topic hook:** when the topic is programming, any code shown in lessons must honor the relevant conventions (`dev`, `typescript`, `python`) via plugin-main's 3-step convention lookup.

## Reference

Extract reusable knowledge — syntax, algorithms, flowcharts, pose sequences, glossaries — into `reference/NNNN-<reference-slug>.html`. References are the compressed essence of lessons, designed for quick review; unlike lessons, they *will* be revisited.

## Glossary promotion

Promote terms into `GLOSSARY.md` per [./GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md) **only after the user demonstrably understands them** — compressing a concept into a tight definition is itself evidence of learning. Be opinionated; once a term is in the glossary, adhere to it everywhere.
