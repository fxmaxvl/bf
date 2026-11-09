#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
mkdir -p docs
cat > docs/NOTES.md <<'MD'
# Release notes

Our seamless release process ships every build in minutes.

Let me be clear: the pipeline is robust. It adds a retry step, highlighting the team's care for quality.

Experts agree that small releases fail less often. The cause is simple; each build changes little.

In conclusion, the new process saves time.
MD
git add -A
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
