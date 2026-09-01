#!/usr/bin/env bash
# Probe the install state of the engineering guidelines at the user tier.
# Output: single JSON object. Performs no writes.
# Usage: probe.sh <PLUGIN_ROOT>

set -euo pipefail

PLUGIN_ROOT="${1:?usage: probe.sh <PLUGIN_ROOT>}"
SRC="$PLUGIN_ROOT/conventions/guidelines.md"
DEST_DIR="$HOME/.bf/conventions"
DEST="$DEST_DIR/guidelines.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
# Tilde form: portable across machines, and CLAUDE.md @-imports resolve it.
IMPORT_LINE="@~/.bf/conventions/guidelines.md"

# --- source ---
if [[ -f "$SRC" ]]; then src_state="present"; else src_state="missing"; fi

# --- destination file ---
if [[ ! -f "$DEST" ]]; then
  dest_state="absent"
elif [[ "$src_state" == "present" ]] && cmp -s "$SRC" "$DEST"; then
  dest_state="current"
else
  dest_state="differs"
fi

# --- CLAUDE.md import ---
if [[ ! -f "$CLAUDE_MD" ]]; then
  import_state="no_claude_md"
# Matches any prior form: tilde, absolute, or relative.
elif grep -qE '^@[^[:space:]]*\.bf/conventions/guidelines\.md[[:space:]]*$' "$CLAUDE_MD" 2>/dev/null; then
  import_state="present"
else
  import_state="absent"
fi

# --- writability ---
if [[ "$import_state" == "no_claude_md" ]]; then
  [[ -w "$HOME/.claude" || ! -e "$HOME/.claude" ]] && claude_md_writable=true || claude_md_writable=false
else
  [[ -w "$CLAUDE_MD" ]] && claude_md_writable=true || claude_md_writable=false
fi

printf '{"src":"%s","src_path":"%s","dest":"%s","dest_path":"%s","dest_dir":"%s","import":"%s","claude_md":"%s","claude_md_writable":%s,"import_line":"%s"}\n' \
  "$src_state" "$SRC" "$dest_state" "$DEST" "$DEST_DIR" "$import_state" "$CLAUDE_MD" "$claude_md_writable" "$IMPORT_LINE"
