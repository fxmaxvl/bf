#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
bash "$SCRIPT_DIR/install.sh" off >/dev/null 2>&1 || true

exit 0
