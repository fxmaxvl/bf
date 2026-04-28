#!/usr/bin/env bash
# finalize-git.sh — Stage, commit, push, and open a PR.
# Replaces ~6 individual model-directed git/gh bash calls in Phase 6.
# Usage:
#   bash finalize-git.sh \
#     --commit-msg "<message>" \
#     --pr-title "<title>" \
#     --pr-body-file "<path>" \
#     [--closes-issue <n>] \
#     [--jira-url <url>]
#
# Outputs the PR URL on stdout.
# Skips the commit step if there are no uncommitted changes.

set -euo pipefail

COMMIT_MSG=""
PR_TITLE=""
PR_BODY_FILE=""
CLOSES_ISSUE=""
JIRA_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit-msg)   COMMIT_MSG="$2";   shift 2 ;;
        --pr-title)     PR_TITLE="$2";     shift 2 ;;
        --pr-body-file) PR_BODY_FILE="$2"; shift 2 ;;
        --closes-issue) CLOSES_ISSUE="$2"; shift 2 ;;
        --jira-url)     JIRA_URL="$2";     shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

for VAR in COMMIT_MSG PR_TITLE PR_BODY_FILE; do
    if [[ -z "${!VAR}" ]]; then
        FLAG=$(echo "$VAR" | tr '[:upper:]_' '[:lower:]-')
        echo "Error: --${FLAG} is required" >&2
        exit 1
    fi
done

if [[ ! -f "$PR_BODY_FILE" ]]; then
    echo "Error: PR body file not found: $PR_BODY_FILE" >&2
    exit 1
fi

# Build final PR body
BODY="$(cat "$PR_BODY_FILE")"
if [[ -n "$CLOSES_ISSUE" ]]; then
    BODY="${BODY}"$'\n\n'"Closes #${CLOSES_ISSUE}"
fi
if [[ -n "$JIRA_URL" ]]; then
    BODY="${BODY}"$'\n\n'"Jira: ${JIRA_URL}"
fi

# Stage everything except .bfeature-temp, commit if anything is staged
DIRTY=$(git status --porcelain | grep -v '^??' || true)
if [[ -n "$DIRTY" ]]; then
    git add -A -- ':!.claude/.bfeature-temp'
    STAGED=$(git diff --cached --name-only)
    if [[ -n "$STAGED" ]]; then
        git commit -m "$COMMIT_MSG"
    fi
fi

git push -u origin HEAD

PR_URL=$(gh pr create --title "$PR_TITLE" --body "$BODY")
echo "$PR_URL"
