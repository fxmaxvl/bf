---
type: regex
weight: 2
target:
  source: file
  path: scripts/new-post.sh
match: contains
flags: m
---
^\s*(source|\.)\s+.*lib/strings\.sh
