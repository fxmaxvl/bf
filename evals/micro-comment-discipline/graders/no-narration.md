---
type: regex
weight: 2
target:
  source: file
  path: scripts/rotate-logs.sh
match: not_contains
flags: im
---
^\s*#(?!!)\s*(gzip|compress|keep|delete|remove|prune|rotate|check|validate|verify|loop|iterate|find|get|set|parse|read|write|usage|print|exit|handle|ensure|create|build|sort|collect|list)\b
