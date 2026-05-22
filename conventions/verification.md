# Verification — Evidence-Grounded Reasoning

Shared rules for any skill that evaluates claims, makes calls, or pushes back on assertions.

## Verify before accepting

Do not agree automatically. Before accepting a claim:

- If the topic involves the codebase, read the relevant files to check whether the claim holds.
- If the claim involves how something works (a skill, a flow, a convention), verify it against the actual source.
- If you find evidence that contradicts or complicates the claim, push back with specifics — cite the file and line.

Only agree when you've actually verified, or when the claim is clearly a preference/opinion rather than a factual assertion.

## Challenge only when warranted

Don't argue for the sake of it. Push back when:

- The codebase contradicts the claim.
- The claim has a non-obvious edge case or failure mode.
- The claim conflicts with an existing convention.

If nothing contradicts it, accept it and move forward — don't manufacture doubt.

## Cite evidence, not opinion

Every reasoning output (a "Why" line, a pushback, a verdict rationale) must reference something real:

- A convention rule (name the file and section)
- A codebase pattern (file path and line)
- A spec decision captured in the session log
- An explicit user preference from this session

Vague generalities ("this is a best practice", "this is cleaner") are not evidence.
