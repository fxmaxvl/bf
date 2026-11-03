#!/usr/bin/env bash
# rename-only.sh: Decide whether a change is only renames and path or module string edits.
# Usage: bash rename-only.sh [--base <ref>]
#   --base   Ref to diff against (default: origin/HEAD, then origin/main, origin/master, main, master, as changed-packages.sh)
# Output: "skip: true" when every changed entry is a pure rename (R100) or a modification whose
#   added and removed lines pair up in order, hunk by hunk, and differ only inside single- or
#   double-quoted path or module literals (no whitespace, no `$`, backtick or parenthesis, and
#   either a "/" or a dotted name such as "pkg.mod"), else "skip: false". The quote kind must stay
#   the same. A string like "admin", a prose edit between two quotes, moved lines or an untracked
#   file outside .bf/ is a real change and gives false.
#   An empty diff, an add, a delete, a copy or a rename that also carries edits gives false: a gate
#   skipped over real code costs more than the two gates it saves.
# The diff runs from the merge base to the working tree: micro asks before it commits, so the
#   task's edits are usually uncommitted. Run it from inside the repo to check.
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

from=$(git merge-base "$base" HEAD 2>/dev/null) || { echo "skip: false"; exit 0; }
[[ -z "$(git ls-files --others --exclude-standard -- . ':!.bf/')" ]] || { echo "skip: false"; exit 0; }
entries=$(git diff --name-status -M "$from" 2>/dev/null) || { echo "skip: false"; exit 0; }
[[ -n "$entries" ]] || { echo "skip: false"; exit 0; }

python3 - "$from" "$entries" <<'PY'
import re
import subprocess
import sys

base, entries = sys.argv[1], sys.argv[2]
strings = re.compile(r'''"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`]*`''')
literal = re.compile(r"[^\s$`()]+")
module = re.compile(r"[A-Za-z_@][\w@-]*(\.[\w-]+)+")
hunk = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")

def mask(m):
    quote, body = m.group(0)[0], m.group(0)[1:-1]
    if quote != "`" and literal.fullmatch(body) and ("/" in body or module.fullmatch(body)):
        return quote * 2
    return m.group(0)

def only_string_edits(path):
    r = subprocess.run(["git", "diff", "-U0", base, "--", path], capture_output=True, text=True)
    hunks, cur = [], None
    for line in r.stdout.splitlines():
        h = hunk.match(line)
        if h:
            old = int(h.group(1)) if h.group(1) is not None else 1
            new = int(h.group(2)) if h.group(2) is not None else 1
            if old != new:
                return False
            cur = ([], [])
            hunks.append(cur)
        elif cur is None:
            continue
        elif line.startswith("-"):
            cur[0].append(strings.sub(mask, line[1:]))
        elif line.startswith("+"):
            cur[1].append(strings.sub(mask, line[1:]))
    return bool(hunks) and all(removed == added for removed, added in hunks)

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
