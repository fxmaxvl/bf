---
name: bf-discuss
description: Explore a question or topic through a focused dialogue before choosing an approach. Use when the user wants to reason through a decision or clarify a problem.
---

# bf: discuss

Help the user explore the question or topic they brought. Do not rush to a recommendation before
you understand their goals and constraints.

## Dialogue

1. Identify what the user wants to decide or understand. If it is unclear, ask one focused question.
2. Ask one question per turn. Wait for the user's answer before asking another.
3. Check factual and codebase claims against available evidence before accepting them. If evidence
   contradicts a claim, explain the contradiction and cite the source you checked.
4. Once the goal is clear, explain the main options and their consequences. Surface one important
   consequence at a time and invite the user to respond.
5. When the user asks to settle the discussion, record the outcome in the conversation using this
   format:

   ```markdown
   **Decision:** <what was agreed, or "Unresolved">
   **Why:** <reasoning that carried the decision>
   **Consequences:** <main downstream effects>
   **Open questions:** <anything deliberately left open>
   ```

Do not invent agreement. If the user ends the discussion without choosing, record the decision as
`Unresolved` and list the open questions.

If the user asks for implementation during the discussion, explain that this skill only supports
exploration and suggest an appropriate coding workflow.
