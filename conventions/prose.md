# Prose Conventions

Write prose for people in clear technical language, based on ASD-STE100 Simplified Technical English (STE). The goal is plain, exact text with no "AI slop".

Adapted from [jjsnack/technical-language-skill](https://github.com/jjsnack/technical-language-skill). The pattern catalog also draws on [petergyang/no-ai-slop](https://github.com/petergyang/no-ai-slop) (MIT). The standard itself is free at https://asd-ste100.org. It is copyrighted, so do not paste it.

## Scope

- **Governed:** all prose written for people. That includes chat replies, generated reports and specs, commit and PR text, decision records, docs, code comments, and user-facing error and log messages in code.
- **Examples are governed too.** Sample output, output templates, and format lines inside a skill or prompt file are text for people, because the model copies them into its output. Write them under these rules.
- **Not governed:** code, identifiers, command syntax, quoted material, and the instructions in model-facing files (skill files, conventions, agent prompts).
- **Format wins.** Structure stays as the skill defines it: headings, block headers, table columns, keys, banners, and any literal a script or another skill parses. This convention governs the words inside that structure.
- Not for marketing copy, essays, or anything that needs a voice. STE strips voice on purpose.

## Rules

WORDS
- Use one name for one thing. Do not call the same item by two names.
- Use the short common word: start (not begin), use (not utilize), before (not prior to). The `replace` key of the `prose-lint` block below is the full list.
- Give each word one meaning. "fall" means to move down, not to decrease.
- No marketing adjectives: seamless, robust, powerful. The `banned` key of the `prose-lint` block is the full list.
- No hollow intensifiers: genuinely, truly, "worth noting". State the fact. The `banned` key also lists these.
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
- No em dash. Use a comma, a period, or two sentences. (STE permits the em dash. This convention removes it because it is a common slop marker.)

STRUCTURE
- One topic per paragraph, at most six sentences. Keep tense and point of view constant inside a paragraph.
- Steps go in a numbered list, one action per item, imperative form. Put a condition before its command: "If the build fails, read the log".
- Put a warning before the step it applies to.
- No bold in the middle of a sentence for emphasis. No heading over a two-sentence section. No bullets where two sentences of prose read better. No emoji in headings.

PATTERNS
- Throat-clearing opener (`Let me be clear`): delete it and state the point.
- Faux insight (`What most people get wrong`): delete the setup and make the claim stand alone.
- Colon reveal (`The detail that makes it work: a separate agent grades it`): write a plain sentence. Use a colon for a list, a label or a quote.
- Superficial analysis (`adds file search, highlighting the team's commitment`): delete the trailing "-ing" clause or replace it with a fact.
- Importance puffery (`plays a vital role`, `stands as a testament`): state the fact and let the reader judge.
- Interpretive metadiscourse (`The key point is`, `As you can see`): delete the aside or add support.
- Weasel attribution (`Experts agree`, `Studies show`): name the source or flag the claim. If you have no source, ask. Never invent one.
- Fake-strong verb (`serves as a hub`): write "is" or "has", or name what the thing does.
- Synonym cycling (`the agent`, then `the assistant`, then `the tool`): repeat the one clear word.
- Negative listing (`Not a plan. Not a spec. A sketch.`): state the last item only.
- Dramatic fragments (`That's it. That's the whole thing.`): write complete sentences.
- Robotic rhythm: vary the sentence shape only where it helps the point.
- Rhetorical setup (`What if I told you`, `Plot twist:`): drop it and make the point.
- Fake-profound kicker (a final line that turns the point into a metaphor): delete the line. Do not rewrite it into a better metaphor. End on the last concrete sentence.
- Summary recap (`In conclusion`, `Overall`): end on the last concrete point or the next action.
- The lint reports the phrase and "-ing" patterns and the formatting patterns as soft findings. The other patterns need judgment.

## Lint rules

`skills/plain/scripts/prose-lint.sh` reads this block. Each line is `key: value`. Lists are space-separated, `from>to` is a pair, and `_` stands for one space. The `empty` key lists words that add nothing. The `pattern` key lists `phrase>name` pairs, and the lint reports the phrase with the pattern name. The `ing_tail` key lists the "-ing" verbs that the lint reports after a comma. No soft key changes the exit code. The lint skips a key it does not know. Keep the block free of em dashes and semicolons.

```prose-lint
hard: em_dash semicolon contraction
cap_instruction: 20
cap_descriptive: 25
long_reply_words: 150
replace: utilize>use leverage>use begin>start commence>start initiate>start facilitate>help ensure>make_sure prior_to>before subsequent_to>after regarding>about obtain>get acquire>get demonstrate>show additionally>also furthermore>also moreover>also in_order_to>to has_the_ability_to>can made_a_decision>decided with_regard_to>about in_terms_of>in
banned: seamless robust powerful cutting-edge effortless world-class battle-tested genuinely truly worth_noting it_is_important_to_note delve delves foster fosters fostering tapestry realm beacon multifaceted meticulous intricate paramount transformative elevate embark supercharge ever-evolving game-changer game_changer streamline streamlined empower empowers paradigm_shift
empty: just simply actually literally fundamentally inherently crucially importantly
pattern: let_me_be_clear>throat_clearing what_most_people_get_wrong>faux_insight stands_as_a_testament>importance_puffery plays_a_vital_role>importance_puffery pivotal_moment>importance_puffery as_you_can_see>metadiscourse the_key_point_is>metadiscourse experts_agree>weasel_attribution studies_show>weasel_attribution many_argue>weasel_attribution widely_regarded_as>weasel_attribution serves_as>fake_strong_verb what_if_i_told_you>rhetorical_setup in_conclusion>summary_recap
ing_tail: highlighting underscoring showcasing reflecting emphasizing
```

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
9. Could a sentence move unchanged to another product or company? Cut it or make it specific.
10. Would it sound natural read aloud to a sharp colleague?

## Limits

These rules fix the form of slop. They are not an AI-text detector. They can over-fire on second-language or already-terse technical prose, so prefer minimal edits there. They cannot make a hollow paragraph true: if a passage states no fact, flag it and do not invent one.
