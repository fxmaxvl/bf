---
type: regex
weight: 2
target:
  source: file
  path: docs/GUIDE.md
match: not_contains
flags: i
---
\b(seamless(ly)?|robust|battle-tested|leverages?|facilitate|lightning-fast|ensure|prior to|in order to|additionally|furthermore|genuinely|empowering|unlock|it is important to note)\b
