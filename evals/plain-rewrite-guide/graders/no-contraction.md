---
type: regex
target:
  source: file
  path: docs/GUIDE.md
match: not_contains
flags: i
---
\b\w+['’](t|re|ve|ll|d|m)\b
