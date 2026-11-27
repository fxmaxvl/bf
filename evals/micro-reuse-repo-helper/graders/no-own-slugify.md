---
type: regex
weight: 2
target:
  source: file
  path: scripts/new-post.sh
match: not_contains
flags: m
---
^\s*(function\s+)?slugify\s*(\(\s*\))?\s*\{
