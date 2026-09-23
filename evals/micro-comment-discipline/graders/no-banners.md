---
type: regex
target:
  source: file
  path: scripts/rotate-logs.sh
match: not_contains
flags: m
---
^\s*#\s*[-=#*~]{4,}
