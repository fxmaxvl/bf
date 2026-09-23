---
type: llm
weight: 2
---
PASS only if the response gives a verdict on the specific point asked (decide vs consilium as autopilot's default oracle) for that one section of the document.
FAIL if the response reframes the whole architecture overview as the decision, e.g. says the real task is choosing an oracle, proposes restructuring the document around this question, or recommends abandoning the overview in favour of acting on the decision.
