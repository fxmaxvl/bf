#!/usr/bin/env bash
# finalize-git.sh — Stage, commit, push, and open a PR.
# Replaces ~6 individual model-directed git/gh bash calls in Phase 6.
# Usage:
#   bash finalize-git.sh \
#     --commit-msg "<message>" \
#     --pr-title "<title>" \
#     --pr-body "<body text>" \
#     [--baseline <file>] \
#     [--add <path>]... \
#     [--leave-untracked] \
#     [--closes-issue <n>] \
#     [--jira-url <url>]
#
# Stages tracked edits and deletions anywhere in the repo, the untracked files named with --add,
# and .bf/conventions/. --baseline names the NUL-delimited list of files that were untracked when
# the session started (state-ops.sh paths.untracked_baseline). Untracked files not in it were made
# during the session and are staged too. Without --baseline, every untracked file needs --add.
# --add takes paths relative to the current directory or absolute. It skips paths under .bf/.
# An untracked directory that holds its own .git (a nested clone or a worktree) is skipped unless
# named with --add, so it cannot land in the commit as a gitlink.
#
# Exit 3: untracked files outside .bf/ that are neither named with --add nor new since the
# baseline. The list goes to stderr. Rerun with --add for the files that belong to the change, or
# with --leave-untracked to commit without them.
# Exit 1 before staging: an --add path is missing, ignored, or outside the repo.
# Exit 4: the branch already has a PR that is MERGED or CLOSED, so a push would never reach the
# base branch. The state and URL go to stderr. Start a new branch from HEAD and rerun.
# Nothing is staged or pushed on any of these exits.
#
# Outputs the PR URL on stdout.
# Skips the commit step if there are no uncommitted changes.

set -euo pipefail

COMMIT_MSG=""
PR_TITLE=""
PR_BODY=""
CLOSES_ISSUE=""
JIRA_URL=""
ADD=()
BASELINE=""
LEAVE_UNTRACKED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit-msg)   COMMIT_MSG="$2";   shift 2 ;;
        --pr-title)     PR_TITLE="$2";     shift 2 ;;
        --pr-body)      PR_BODY="$2";      shift 2 ;;
        --closes-issue) CLOSES_ISSUE="$2"; shift 2 ;;
        --jira-url)     JIRA_URL="$2";     shift 2 ;;
        --add)          ADD+=("$2");       shift 2 ;;
        --baseline)     BASELINE="$2";     shift 2 ;;
        --leave-untracked) LEAVE_UNTRACKED=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

for VAR in COMMIT_MSG PR_TITLE PR_BODY; do
    if [[ -z "${!VAR}" ]]; then
        FLAG=$(echo "$VAR" | tr '[:upper:]_' '[:lower:]-')
        echo "Error: --${FLAG} is required" >&2
        exit 1
    fi
done

# Build final PR body
BODY="$PR_BODY"
if [[ -n "$CLOSES_ISSUE" ]]; then
    BODY="${BODY}"$'\n\n'"Closes #${CLOSES_ISSUE}"
fi
if [[ -n "$JIRA_URL" ]]; then
    BODY="${BODY}"$'\n\n'"Jira: ${JIRA_URL}"
fi

ROOT=$(git rev-parse --show-toplevel)
PREFIX=$(git rev-parse --show-prefix)

# git ls-files prints repo-relative paths, so every --add value is made repo-relative before the
# comparison. The parent is resolved physically because the toplevel git prints is physical
# (/var and /private/var differ on macOS).
repo_relative() {
    local p="$1" dir
    if [[ "$p" == /* ]]; then
        dir=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) && p="$dir/$(basename "$p")"
        [[ "$p" == "$ROOT"/* ]] && p="${p#"$ROOT"/}"
    else
        p="$PREFIX${p#./}"
    fi
    printf '%s' "$p"
}
NAMED=()
for A in ${ADD[@]+"${ADD[@]}"}; do
    A=$(repo_relative "$A")
    if [[ "$A" == .bf || "$A" == .bf/* ]]; then
        echo "Note: skipping --add $A: .bf/ holds workflow artifacts (.bf/conventions/ is staged on its own)." >&2
        continue
    fi
    NAMED+=("$A")
done
cd "$ROOT"

PR_INFO=$(gh pr view --json state,url -q '.state + " " + .url' 2>/dev/null || true)
PR_STATE=${PR_INFO%% *}
EXISTING_PR=${PR_INFO#* }
if [[ "$PR_STATE" == MERGED || "$PR_STATE" == CLOSED ]]; then
    echo "Error: the PR for this branch is $PR_STATE ($EXISTING_PR). Nothing was staged or pushed. Start a new branch from HEAD and rerun." >&2
    exit 4
fi

in_list() {
    local f="$1" a; shift
    for a in "$@"; do
        [[ "$f" == "$a" || "$f" == "${a%/}/"* ]] && return 0
    done
    return 1
}
AT_START=()
if [[ -n "$BASELINE" && -f "$BASELINE" ]]; then
    while IFS= read -r -d '' F; do AT_START+=("$F"); done < "$BASELINE"
elif [[ -n "$BASELINE" ]]; then
    echo "Note: baseline $BASELINE not found; every untracked file needs --add." >&2
    BASELINE=""
fi

# .bf/ holds workflow artifacts, never part of the change, except .bf/conventions/ (the project
# convention tier, which is shared through the repo). An exclude pathspec cannot be re-included,
# so that tier is staged on its own.
STAGE=(${NAMED[@]+"${NAMED[@]}"})
STRAY=()
while IFS= read -r -d '' F; do
    if [[ "$F" == */ && -e "${F}.git" ]]; then
        echo "Note: skipping $F: it is a nested git repo." >&2
        continue
    fi
    in_list "$F" ${NAMED[@]+"${NAMED[@]}"} && continue
    if [[ -n "$BASELINE" ]] && ! in_list "$F" ${AT_START[@]+"${AT_START[@]}"}; then
        STAGE+=("$F")
    else
        STRAY+=("$F")
    fi
done < <(git ls-files -z --others --exclude-standard -- . ':!.bf')
if [[ ${#STRAY[@]} -gt 0 && "$LEAVE_UNTRACKED" -eq 0 ]]; then
    {
        echo "Error: untracked files that are not part of the change:"
        printf '  %s\n' "${STRAY[@]}"
        echo "Pass --add <path> for each file that belongs to the change, or --leave-untracked to commit without them."
    } >&2
    exit 3
fi

if [[ ${#STAGE[@]} -gt 0 ]] && ! git add --dry-run -- "${STAGE[@]}" >/dev/null; then
    echo "Error: cannot stage the files above; nothing was staged." >&2
    exit 1
fi
git add -u -- . ':!.bf'
[[ ${#STAGE[@]} -eq 0 ]] || git add -- "${STAGE[@]}"
[[ -z "$(git status --porcelain -- .bf/conventions)" ]] || git add -A -- .bf/conventions
if [[ -n "$(git diff --cached --name-only)" ]]; then
    git commit -m "$COMMIT_MSG"
fi

git push -u origin HEAD

if [[ -n "$EXISTING_PR" ]]; then
    gh pr edit --title "$PR_TITLE" --body "$BODY"
    PR_URL="$EXISTING_PR"
else
    PR_URL=$(gh pr create --title "$PR_TITLE" --body "$BODY")
fi
echo "$PR_URL"
