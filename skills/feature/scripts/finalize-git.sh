#!/usr/bin/env bash
# finalize-git.sh — Stage, commit, push, and open a PR.
# Replaces ~6 individual model-directed git/gh bash calls in Phase 6.
# Usage:
#   bash finalize-git.sh \
#     --commit-msg "<message>" \
#     --pr-title "<title>" \
#     --pr-body "<body text>" \
#     [--closes-issue <n>] \
#     [--jira-url <url>]
#
# Outputs the PR URL on stdout.
# Skips the commit step if there are no uncommitted changes.

set -euo pipefail

COMMIT_MSG=""
PR_TITLE=""
PR_BODY=""
CLOSES_ISSUE=""
JIRA_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit-msg)   COMMIT_MSG="$2";   shift 2 ;;
        --pr-title)     PR_TITLE="$2";     shift 2 ;;
        --pr-body)      PR_BODY="$2";      shift 2 ;;
        --closes-issue) CLOSES_ISSUE="$2"; shift 2 ;;
        --jira-url)     JIRA_URL="$2";     shift 2 ;;
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

# .bf/ holds workflow artifacts, never part of the change, except .bf/conventions/ — the project
# convention tier, which is shared through the repo. An exclude pathspec cannot be re-included, so
# that tier is staged on its own.
DIRTY=$(git status --porcelain -- . ':!.bf')
CONVENTIONS_DIRTY=$(git status --porcelain -- .bf/conventions)
if [[ -n "$DIRTY" || -n "$CONVENTIONS_DIRTY" ]]; then
    [[ -z "$DIRTY" ]] || git add -A -- . ':!.bf'
    [[ -z "$CONVENTIONS_DIRTY" ]] || git add -A -- .bf/conventions
    STAGED=$(git diff --cached --name-only)
    if [[ -n "$STAGED" ]]; then
        git commit -m "$COMMIT_MSG"
    fi
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
