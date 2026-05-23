#!/usr/bin/env bash
# Delegates to session-start-cleanup.sh — same cleanup logic, different trigger event.
exec "$(dirname "$0")/session-start-cleanup.sh" "$@"
