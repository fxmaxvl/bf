---
type: regex
target:
  source: file
  path: docs/GUIDE.md
match: contains
flags: m
---
^\$ make build; make test$
