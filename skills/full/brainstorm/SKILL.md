---
name: brainstorm-gather
description: Ask the user clarifying questions one-at-a-time to gather requirements for an idea. Saves Q&A to the artifacts dir for the generate phase.
disable-model-invocation: true
argument-hint: [idea description]
---

Ask the user one question at a time to gather requirements for their idea.
Each question should build on the previous response, gradually filling in gaps.
Do **not** skip steps or ask multiple questions at once.

## Input

Run the helper script to load state:

```
bash "$(find ~/.claude -name state-ops.sh -path '*/full/scripts/*' 2>/dev/null | head -1)"
```

This gives you `slug`, `build_timestamp`, `paths.qa`, `jira` (with `enabled`, `ticket_key`), and `github_issue` (with `enabled`, `number`).

## Jira-sourced ideas

If `jira.enabled` is `true`, you will receive a pre-synthesized description built from the ticket's description and comments. This gives you a richer starting point — you may need fewer clarifying questions, but still ask if anything is ambiguous or underspecified.

## GitHub-sourced ideas

If `github_issue.enabled` is `true`, you will receive the issue title and body as the description. This gives you a richer starting point — you may need fewer clarifying questions, but still ask if anything is ambiguous or underspecified.

## Knowing when to stop

Stop asking questions when you have enough information to hand off to spec generation:
- The user confirms they've covered everything
- All major ambiguities in the original idea have been clarified
- Further questions would be splitting hairs

## When the user can't answer a question

If the user says they don't know the answer and asks to post the question to Jira, **stop the gather** and hand control back to the parent `bfeature` skill. The parent will handle posting the question to Jira and pausing the flow. Do not attempt to post to Jira yourself.

## Output

Once you have enough information, save a Q&A summary to the path at `paths.qa` (from `state-ops.sh`). Format:

```markdown
# Brainstorm Q&A

## Original Idea
<original idea text>

## Clarifications
**Q: <question>**
A: <answer>

**Q: <question>**
A: <answer>
```

Do **not** generate a spec — that is handled by the generate phase.

Here is the idea:
$ARGUMENTS
