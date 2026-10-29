# Prose Conventions

Write prose for people in clear technical language, based on ASD-STE100 Simplified Technical English (STE). The goal is plain, exact text with no "AI slop".

Adapted from [jjsnack/technical-language-skill](https://github.com/jjsnack/technical-language-skill). The standard itself is free at https://asd-ste100.org. It is copyrighted, so do not paste it.

## Scope

- **Governed:** chat replies, `.bf/` artifacts, commit messages, PR titles and bodies, PR comment replies, ADRs, design docs, READMEs and other human docs, code comments, and user-facing error and log messages in code.
- **Not governed:** code, identifiers, command syntax, quoted material, and model-facing instruction files (any `SKILL.md`, `conventions/*.md`, agent prompts).
- **Format wins.** A skill's fixed output format (banners, block headers, tables, JSON) stays as the skill defines it. This convention governs the sentences inside it.
- Not for marketing copy, essays, or anything that needs a voice. STE strips voice on purpose.

## Rules

WORDS
- Use one name for one thing. Do not call the same item by two names.
- Use the short common word: start (not begin/commence/initiate), use (not utilize/leverage), help (not facilitate), make sure (not ensure), before (not prior to), after (not subsequent to), about (not regarding), get (not obtain/acquire), show (not demonstrate), also (not additionally/furthermore/moreover).
- Give each word one meaning. "fall" means to move down, not to decrease.
- No marketing adjectives: seamless, robust, powerful, cutting-edge, effortless, world-class, battle-tested.
- No hollow intensifiers: genuinely, truly, "worth noting", "it is important to note". State the fact.
- No noun clusters of more than three nouns. Break them up with articles and prepositions.
- American spelling.

VERBS
- Active voice. Name the actor and put it first: "the parser reads the file".
- Use a verb for an action: "analyze the log", not "perform an analysis of the log".
- No phrasal verbs where a plain verb exists: "start", not "spin up". "contact", not "reach out".
- No stacked auxiliaries. Not "this may help to improve". Write "this improves X".
- No "-ing" main verb where a simple tense works.

SENTENCES
- One instruction per sentence.
- No contractions. Keep the articles: a, an, the, this, these.
- No "not X, it is Y" pivot, including the split form across two sentences. State the point directly.

PUNCTUATION
- No semicolons. Write two sentences.
- No em dash. Use a comma, a period, or two sentences. (STE permits the em dash. bf removes it because it is a common slop marker.)

STRUCTURE
- One topic per paragraph, at most six sentences. Keep tense and point of view constant inside a paragraph.
- Steps go in a numbered list, one action per item, imperative form. Put a condition before its command: "If the build fails, read the log".
- Put a warning before the step it applies to.

## Modes

Pick the mode from the text. Do not ask.

- **strict:** procedures, runbooks, numbered steps, warnings, error messages. Hard caps: 20 words for an instruction sentence, 25 for a descriptive sentence.
- **flavored:** all other prose. Apply every rule. The length caps are targets, not hard limits, so the text keeps enough range to read naturally.

## Self-lint

Run this before returning text. Fix what fails.

1. Any sentence over the cap? Split it.
2. Any semicolon or em dash? Replace it.
3. Any contraction? Expand it.
4. Any passive voice with a known actor? Make it active.
5. Any "-ing" main verb, nominalization, or phrasal verb? Use a plain verb.
6. Any "not X, it is Y" pivot or hollow intensifier? State the point directly.
7. Any noun cluster of four or more nouns? Break it up.
8. Same thing named two ways? Pick one name.

## Limits

These rules fix the form of slop. They are not an AI-text detector. They can over-fire on second-language or already-terse technical prose, so prefer minimal edits there. They cannot make a hollow paragraph true: if a passage states no fact, flag it and do not invent one.
