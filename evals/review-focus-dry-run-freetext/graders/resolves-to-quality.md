---
type: llm
weight: 2
---
Find the printed dry-run preview. PASS only if it names `quality` as the resolved focus lens (the lens name itself, not a paraphrase such as "readability") and lists the review Agent plus both the complexity and consistency gates as the agents that would run.
FAIL if it reports a full or unfocused review, describes the focus only in its own words without resolving it to a named lens, or treats "can we make this look nicer" as a file or path scope.
