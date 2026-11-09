#!/usr/bin/env bash
set -euo pipefail
origin=$(mktemp -d)/origin.git
git init -q --bare "$origin"
git init -q -b main
git config user.email eval@example.com
git config user.name eval
git config commit.gpgsign false
git remote add origin "$origin"
mkdir -p src
printf '#!/usr/bin/env bash\nn=$1\necho "hello $n"\n' > src/greet.sh
git add src/greet.sh
git commit -q -m init
git push -q -u origin main
git checkout -q -b feat/rename-n
printf '#!/usr/bin/env bash\nname=$1\necho "hello $name"\n' > src/greet.sh
sessions="$PWD/.bf/sessions"
mkdir -p "$sessions"
prefix=20261106T15-rename-n
printf '# Micro Instruction\n\n## QA\nin src/greet.sh, rename the variable `n` to `name`.\n' > "$sessions/$prefix-temp.md"
: > "$sessions/$prefix-untracked-at-start"
cat > "$sessions/build-state.json" <<JSON
{
  "idea": "in src/greet.sh, rename the variable n to name.",
  "slug": "rename-n",
  "build_timestamp": "20261106T15",
  "mode": "micro",
  "phase": "finalize",
  "phase_status": "awaiting_approval",
  "github_issue": {"enabled": false, "number": null},
  "jira": {"enabled": false, "ticket_key": null, "ticket_url": null, "pending_questions": null},
  "collect_todos": null,
  "commit_only": null,
  "parallel_audit": true,
  "auto_fix_style": false,
  "skip_plan_gates": false,
  "artifacts": {"spec": null, "plan": null, "todo": null, "backlog": null},
  "created_at": "2026-11-06T15:00:00+00:00",
  "updated_at": "2026-11-06T15:00:00+00:00"
}
JSON
