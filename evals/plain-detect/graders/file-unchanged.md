---
type: regex
weight: 2
target:
  source: file
  path: docs/NOTES.md
match: contains
---
^# Release notes\n\nOur seamless release process ships every build in minutes\.\n\nLet me be clear: the pipeline is robust\. It adds a retry step, highlighting the team's care for quality\.\n\nExperts agree that small releases fail less often\. The cause is simple; each build changes little\.\n\nIn conclusion, the new process saves time\.\n\nThe detail that makes it work: every build changes little\.\n$
