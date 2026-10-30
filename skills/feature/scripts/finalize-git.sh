#!/usr/bin/env bash
# finalize-git.sh — Stage, commit, push, and open a PR.
# Replaces ~6 individual model-directed git/gh bash calls in Phase 6.
# Usage:
#   bash finalize-git.sh \
#     --commit-msg "<message>" \
#     --pr-title "<title>" \
#     --pr-body "<body text>" \
#     [--add <path>]... \
#     [--leave-untracked] \
#     [--closes-issue <n>] \
#     [--jira-url <url>]
#
# Stages tracked edits and deletions, the untracked files named with --add, and .bf/conventions/.
# Any other untracked file outside .bf/ stops the run before anything is staged or pushed: the
# list goes to stderr and the exit code is 3. Rerun with --add for the files that belong to the
# change, or with --leave-untracked to commit without them.
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
LEAVE_UNTRACKED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit-msg)   COMMIT_MSG="$2";   shift 2 ;;
        --pr-title)     PR_TITLE="$2";     shift 2 ;;
        --pr-body)      PR_BODY="$2";      shift 2 ;;
        --closes-issue) CLOSES_ISSUE="$2"; shift 2 ;;
        --jira-url)     JIRA_URL="$2";     shift 2 ;;
        --add)          ADD+=("${2#./}");  shift 2 ;;
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

# An untracked file may be a stray the session never made, so only the ones the caller names are
# staged. .bf/ holds workflow artifacts, never part of the change, except .bf/conventions/ (the
# project convention tier, which is shared through the repo). An exclude pathspec cannot be
# re-included, so that tier is staged on its own.
named() {
    local a
    for a in ${ADD[@]+"${ADD[@]}"}; do
        [[ "$1" == "$a" || "$1" == "${a%/}/"* ]] && return 0
    done
    return 1
}
STRAY=()
while IFS= read -r -d '' F; do
    named "$F" || STRAY+=("$F")
done < <(git ls-files -z --others --exclude-standard -- . ':!.bf')
if [[ ${#STRAY[@]} -gt 0 && "$LEAVE_UNTRACKED" -eq 0 ]]; then
    {
        echo "Error: untracked files that are not part of the change:"
        printf '  %s\n' "${STRAY[@]}"
        echo "Pass --add <path> for each file the session created, or --leave-untracked to commit without them."
    } >&2
    exit 3
fi

git add -u -- . ':!.bf'
[[ ${#ADD[@]} -eq 0 ]] || git add -- "${ADD[@]}"
[[ -z "$(git status --porcelain -- .bf/conventions)" ]] || git add -A -- .bf/conventions
if [[ -n "$(git diff --cached --name-only)" ]]; then
    git commit -m "$COMMIT_MSG"
fi

git push -u origin HEAD

EXISTING_PR=$(gh pr view --json url -q '.url' 2>/dev/null || true)
if [[ -n "$EXISTING_PR" ]]; then
    gh pr edit --title "$PR_TITLE" --body "$BODY"
    PR_URL="$EXISTING_PR"
else
    PR_URL=$(gh pr create --title "$PR_TITLE" --body "$BODY")
fi
echo "$PR_URL"
