#!/usr/bin/env bash
# Run state for the layered descent: artifact paths, and which branches have already finished.
# Filenames derive from the repo name, not a timestamp, so a resumed run finds the prior output.
# A branch is complete only once its fragment is on disk — a branch held in context is not
# resumable, which would make the completion record a lie after an interruption.
# Usage:
#   run-state.sh paths
#   run-state.sh init "<scope text>"                 # creates state when absent; scope always refreshed
#   run-state.sh done "<unit path>" "<fragment>"     # records one finished branch
# Output: single-line JSON.
set -euo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo '{"error":"not_a_git_repo"}'; exit 1; }
cd "$root"
repo=$(basename "$root")
dir=".bf/audits"
doc="$dir/$repo-arch-audit.md"
frag="$dir/$repo-arch-audit"
state="$dir/$repo-arch-audit-state.json"

case "${1:-paths}" in
  paths)
    printf '{"root":"%s","doc":"%s","fragments_dir":"%s","state":"%s","state_exists":%s}\n' \
      "$root" "$root/$doc" "$root/$frag" "$root/$state" "$([ -f "$state" ] && echo true || echo false)"
    ;;
  init)
    mkdir -p "$frag"
    python3 - "$state" "$repo" "${2:-}" "$frag" <<'PY'
import json,os,sys,datetime
state,repo,scope,frag=sys.argv[1:5]
s={"repo":repo,"started":datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),"completed_branches":[]}
if os.path.exists(state):
    try: s=json.load(open(state))
    except ValueError: pass
# A branch counts as done only while its fragment survives on disk.
s["completed_branches"]=[b for b in s.get("completed_branches",[]) if os.path.exists(b.get("fragment",""))]
s["scope"]=scope
s["prior_scope_differs"]=bool(s.get("last_scope") and s["last_scope"]!=scope)
s["last_scope"]=scope
json.dump(s,open(state,"w"))
print(json.dumps(s,separators=(",",":")))
PY
    ;;
  done)
    [ -f "$state" ] || { echo '{"error":"no_state"}'; exit 1; }
    unit=${2:?unit path required}
    fragment=${3:?fragment path required}
    [ -s "$fragment" ] || { printf '{"error":"fragment_missing_or_empty","fragment":"%s"}\n' "$fragment"; exit 1; }
    python3 - "$state" "$unit" "$fragment" <<'PY'
import json,sys
state,unit,fragment=sys.argv[1:4]
s=json.load(open(state))
s["completed_branches"]=[b for b in s["completed_branches"] if b.get("unit")!=unit]
s["completed_branches"].append({"unit":unit,"fragment":fragment})
json.dump(s,open(state,"w"))
print(json.dumps(s,separators=(",",":")))
PY
    ;;
  *)
    echo '{"error":"unknown_command"}'; exit 1
    ;;
esac
