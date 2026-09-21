#!/usr/bin/env bash
# Resolve every path bf:design needs, in one call.
#
# Usage:
#   bash design-paths.sh --idea "<idea text>" [--slug <override>]
#
# Emits JSON on stdout:
#   {"timestamp":"YYYYMMDDTHH","slug":"...","temp_dir":"...","qa_path":"...",
#    "doc_path":"...","doc_collided":true|false}
#
# The slug is derived from the idea: ASCII kebab-case, filler words removed,
# capped at 40 chars on a word boundary, falling back to design-<YYYYMMDD>.
# doc_path is resolved against the CURRENT WORKING DIRECTORY (the design doc is
# a named exception to the .bf/ rule) with collisions already resolved to
# -2, -3, ... ; doc_collided says whether a rename happened.
set -euo pipefail

IDEA=""
SLUG_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --idea) IDEA="${2-}"; shift 2 ;;
    --slug) SLUG_OVERRIDE="${2-}"; shift 2 ;;
    *) echo "Error: unknown argument '$1' — expected --idea or --slug" >&2; exit 2 ;;
  esac
done

if [ -z "$IDEA" ] && [ -z "$SLUG_OVERRIDE" ]; then
  echo '{"error":"no_idea","detail":"pass --idea \"<text>\" or --slug <override>"}'
  exit 1
fi

project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$project_root" ]; then TEMP_DIR="$project_root/.bf/sessions"; else TEMP_DIR="$HOME/.bf/sessions"; fi
mkdir -p "$TEMP_DIR"

IDEA="$IDEA" SLUG_OVERRIDE="$SLUG_OVERRIDE" TEMP_DIR="$TEMP_DIR" python3 - <<'PY'
import json, os, re, unicodedata
from datetime import datetime, timezone

FILLER = {"a","an","the","of","to","in","for","on","at","by","with","and","or","but"}
now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y%m%dT%H")

def derive(idea):
    ascii_idea = unicodedata.normalize("NFKD", idea).encode("ascii", "ignore").decode()
    words = [w for w in re.split(r"[^A-Za-z0-9]+", ascii_idea.lower()) if w]
    kept = [w for w in words if w not in FILLER]
    slug = ""
    for w in kept:
        candidate = w if not slug else slug + "-" + w
        if len(candidate) > 40:
            break
        slug = candidate
    if len(slug) <= 3:
        return "design-" + now.strftime("%Y%m%d")
    return slug

slug = os.environ["SLUG_OVERRIDE"].strip() or derive(os.environ["IDEA"])
temp_dir = os.environ["TEMP_DIR"]

cwd = os.getcwd()
base = os.path.join(cwd, slug + "-design")
doc_path, n, collided = base + ".md", 2, False
while os.path.exists(doc_path):
    collided = True
    doc_path = f"{base}-{n}.md"
    n += 1

print(json.dumps({
    "timestamp": timestamp,
    "slug": slug,
    "temp_dir": temp_dir,
    "qa_path": os.path.join(temp_dir, f"{timestamp}-design-qa.md"),
    "doc_path": doc_path,
    "doc_collided": collided,
}))
PY
