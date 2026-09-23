---
type: regex
target:
  source: file
  path: scripts/rotate-logs.sh
match: not_contains
flags: im
---
^\s*#(?!!).*\b(added|fixed|updated|changed|new approach|per review|as requested|ticket|issue|refactor(ed)?)\b
