#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git -c user.email=eval@example.com -c user.name=eval commit -q --allow-empty -m init
