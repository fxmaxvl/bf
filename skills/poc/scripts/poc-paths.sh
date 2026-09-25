#!/usr/bin/env bash
# Resolve the POC directory for bf:poc, in one call.
#
# Usage:
#   bash poc-paths.sh --idea "<idea text>" --where cwd|scratch [--slug <override>]
#
# Emits JSON on stdout:
#   {"slug":"...","poc_dir":"...","brief_path":"...","collided":true|false}
#
# cwd     -> <cwd>/<slug>-poc/        (named exception to the .bf/ rule)
# scratch -> ~/.bf/pocs/<slug>/       (inside the .bf fallback root)
# Collisions resolve to -2, -3, ...; the directory is created, never git-initialised.
set -euo pipefail

IDEA=""
WHERE=""
SLUG_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --idea) IDEA="${2-}"; shift 2 ;;
    --where) WHERE="${2-}"; shift 2 ;;
    --slug) SLUG_OVERRIDE="${2-}"; shift 2 ;;
    *) echo "Error: unknown argument '$1' — expected --idea, --where or --slug" >&2; exit 2 ;;
  esac
done

if [ -z "$IDEA" ] && [ -z "$SLUG_OVERRIDE" ]; then
  echo '{"error":"no_idea","detail":"pass --idea \"<text>\" or --slug <override>"}'
  exit 1
fi
case "$WHERE" in
  cwd|scratch) ;;
  *) echo '{"error":"bad_where","detail":"--where must be cwd or scratch"}'; exit 1 ;;
esac

IDEA="$IDEA" WHERE="$WHERE" SLUG_OVERRIDE="$SLUG_OVERRIDE" python3 - <<'PY'
import json, os, re, unicodedata
from datetime import datetime, timezone

FILLER = {"a","an","the","of","to","in","for","on","at","by","with","and","or","but","poc"}

def derive(idea):
    ascii_idea = unicodedata.normalize("NFKD", idea).encode("ascii", "ignore").decode()
    words = [w for w in re.split(r"[^A-Za-z0-9]+", ascii_idea.lower()) if w and w not in FILLER]
    slug = ""
    for w in words:
        candidate = w if not slug else slug + "-" + w
        if len(candidate) > 40:
            break
        slug = candidate
    if len(slug) <= 3:
        return "poc-" + datetime.now(timezone.utc).strftime("%Y%m%d")
    return slug

slug = os.environ["SLUG_OVERRIDE"].strip() or derive(os.environ["IDEA"])
if os.environ["WHERE"] == "cwd":
    base = os.path.join(os.getcwd(), slug + "-poc")
else:
    base = os.path.join(os.path.expanduser("~"), ".bf", "pocs", slug)

poc_dir, n, collided = base, 2, False
while os.path.exists(poc_dir):
    collided = True
    poc_dir = f"{base}-{n}"
    n += 1
os.makedirs(poc_dir)

print(json.dumps({
    "slug": slug,
    "poc_dir": poc_dir,
    "brief_path": os.path.join(poc_dir, "BRIEF.md"),
    "collided": collided,
}))
PY
