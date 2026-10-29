---
type: regex
weight: 2
target:
  source: file
  path: docs/GUIDE.md
match: contains
---
^(?=[\s\S]*Node 20)(?=[\s\S]*\b8080\b)(?=[\s\S]*\b3\b[^\n]*(time|retr)|[\s\S]*retr[^\n]*\b3\b)(?=[\s\S]*/var/log/orders\.log)(?=[\s\S]*(\bbefore\b[^\n]*\btests?\b|\bfirst\b[^\n]*\btests?\b|\btests?\b[^\n]*\bafter\b))
