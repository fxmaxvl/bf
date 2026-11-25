#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
echo "# fixture" > README.md
git add -A
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
