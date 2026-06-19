# LEARNING-PROFILE.md Format

`LEARNING-PROFILE.md` lives at the **teach root** — `~/.bf/teach/LEARNING-PROFILE.md`, **not** inside a topic's `<slug>/` directory. It is **user-global and shared across every topic**, because how a person best absorbs information is a property of the learner, not the subject. It captures the user's learning style so lessons can be shaped to fit it. When present, it informs lesson format, density, and exercise design in Phase 5; see [SKILL.md](./SKILL.md).

This file has **two mutually exclusive shapes** — an active profile, or a declined marker. The skill branches on which it finds.

## Template — active profile

```md
# Learning Profile

Status: active

## How I absorb information best
{1-3 sentences. The dominant way this person learns — e.g. "by building small things and breaking them," "from worked examples before theory," "by reading the spec end to end first." Concrete over abstract.}

## Preferences
- **Theory vs example:** {example-first | theory-first | balanced}
- **Density & pacing:** {short frequent lessons | longer deep dives | …}
- **Modality:** {diagrams | prose | code | analogies | step-by-step checklists | …}
- **Feedback & practice:** {immediate quizzes | open-ended challenges | real-world tasks | spaced recall | …}

## Dislikes / what doesn't work for me
- {Things that reliably lose this learner — e.g. "walls of unmotivated theory," "toy examples with no real-world tie."}
```

## Template — declined marker

When the user declines to create a profile, write this minimal file instead. Its only job is to record the opt-out so the skill never re-asks.

```md
# Learning Profile

Status: declined

The user declined to create a learning profile. Proceed without one; do not re-ask on future invocations. Delete this file (or ask explicitly) to re-trigger the interview.
```

## Rules

- **Read `Status:` first.** `active` → load and apply the profile. `declined` → skip silently, never re-ask. Absent file → ask once whether to create one.
- **One profile per user.** It is global across all topics. Do not create per-topic copies under `<slug>/`.
- **Concrete over abstract.** "I learn APIs by curling them before reading docs" beats "I'm a hands-on learner."
- **Keep it short.** If the profile runs past a screen, it has stopped being a quick steer and started being a biography. Trim it.
- **Revise when reality shifts.** Learning preferences change. When the user signals a better-fitting style — or asks — update this file. Confirm before overwriting an existing active profile.
- **The declined marker is sticky by design.** Honor it. The only ways back are the user deleting the file or explicitly asking to set up a profile.
- **A profile steers, it does not gate.** A missing or declined profile must never block teaching — fall back to default lesson design (see [SKILL.md](./SKILL.md) Phase 5).
