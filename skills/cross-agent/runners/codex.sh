#!/usr/bin/env bash
# Run a cross-agent bundle with the Codex CLI.
#
# Usage: codex.sh <bundle_dir> <project_root>
# Contract: feeds <bundle_dir>/prompt.md to `codex exec` on stdin, writes the agent's last message to
#   <bundle_dir>/result.md and its full output to <bundle_dir>/run.log, and exits with codex's status.
#   Exit 127 when codex is not on PATH. The sandbox is workspace-write: the skill can write under the
#   project root (its .bf/ artifacts) but has no network, so gh and remote git calls fail.
set -uo pipefail

[ $# -eq 2 ] || { echo "usage: codex.sh <bundle_dir> <project_root>" >&2; exit 2; }
bundle=$1; root=$2
command -v codex >/dev/null || { echo "codex CLI not found on PATH" >&2; exit 127; }
[ -f "$bundle/prompt.md" ] || { echo "$bundle/prompt.md is missing" >&2; exit 2; }

# Exported so the agent can run the skill's `bash "${CLAUDE_PLUGIN_ROOT}/..."` lines as written.
CLAUDE_PLUGIN_ROOT=$(jq -r .plugin_root "$bundle/manifest.json") \
  codex exec -C "$root" -s workspace-write -o "$bundle/result.md" - \
  < "$bundle/prompt.md" > "$bundle/run.log" 2>&1
