#!/usr/bin/env bash
# rename-only.sh: Decide whether a change is only renames and path or module string edits.
# Usage: bash rename-only.sh [--base <ref>]
#   --base   Ref to diff against (default: origin/HEAD, then origin/main, origin/master, main, master, as changed-packages.sh)
# Output: "skip: true" when every changed entry is a pure rename (R100) or a modification whose
#   added and removed lines differ only inside quoted path or module literals (no whitespace, and
#   either a "/" or a dotted name such as "pkg.mod"), else "skip: false". A string like "admin" or
#   a prose edit between two quotes is a real change and gives false.
#   An empty diff, an add, a delete, a copy or a rename that also carries edits gives false: a gate
#   skipped over real code costs more than the two gates it saves.
# The default base is a remote-tracking ref: a local branch behind its remote reports renames as
# unpaired adds, which reads as new code.
set -euo pipefail

base=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) base="${2:?--base needs a ref}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
if [[ -z "$base" ]]; then
  # Same order as changed-packages.sh, so both gates diff against one base.
  base=master
  if ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
    base=${ref#refs/remotes/}
  else
    for b in origin/main origin/master main master; do
      git rev-parse --verify "$b" >/dev/null 2>&1 && { base=$b; break; }
    done
  fi
fi

entries=$(git diff --name-status -M "$base...HEAD" 2>/dev/null) || { echo "skip: false"; exit 0; }
[[ -n "$entries" ]] || { echo "skip: false"; exit 0; }

python3 - "$base" "$entries" <<'PY'
import re
import subprocess
import sys

base, entries = sys.argv[1], sys.argv[2]
strings = re.compile(r'''"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`]*`''')

def mask(m):
    body = m.group(0)[1:-1]
    if re.fullmatch(r"\S+", body) and ("/" in body or re.fullmatch(r"[A-Za-z_@][\w@-]*(\.[\w-]+)+", body)):
        return '""'
    return m.group(0)

def only_string_edits(path):
    r = subprocess.run(["git", "diff", "-U0", f"{base}...HEAD", "--", path],
                       capture_output=True, text=True)
    removed, added = [], []
    for line in r.stdout.splitlines():
        if line.startswith(("---", "+++")):
            continue
        if line.startswith("-"):
            removed.append(strings.sub(mask, line[1:]))
        elif line.startswith("+"):
            added.append(strings.sub(mask, line[1:]))
    return bool(removed) and removed == added

for entry in entries.splitlines():
    fields = entry.split("\t")
    status = fields[0]
    if status == "R100":
        continue
    if status == "M" and only_string_edits(fields[1]):
        continue
    print("skip: false")
    sys.exit(0)
print("skip: true")
PY
