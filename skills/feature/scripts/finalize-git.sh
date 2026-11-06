#!/usr/bin/env bash
# finalize-git.sh — Stage, commit, push, and open a PR.
# Replaces ~6 individual model-directed git/gh bash calls in Phase 6.
# Usage:
#   bash finalize-git.sh \
#     --commit-msg "<message>" \
#     --pr-title "<title>" \
#     --pr-body "<body text>" \
#     [--commit-only] \
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
# session-untracked.sh owns which untracked files count (nested repos are never staged).
# Skips the commit step if there are no uncommitted changes.
# Outputs the PR URL on stdout.
#
# --commit-only skips the PR check, stages and commits as usual, then exits 0 before the push.
# --pr-title and --pr-body are optional with it, and no PR URL is printed.
#
# Exit codes and recovery. This header is the one place that defines them. Show the stderr to the
# user, follow the recovery, then rerun.
# Exit 1: an argument is invalid, or an --add path is missing, ignored, or outside the repo.
#   Nothing is staged. Drop the bad path and rerun.
# Exit 3: untracked files outside .bf/ that are neither named with --add nor new since the
#   baseline. Nothing is staged or pushed. The list goes to stderr. Ask which of them belong to the
#   change (one question), then rerun with --add for those, plus --leave-untracked when any remain.
#   An autonomous run reruns with --leave-untracked: a file that was there before the session never
#   goes into the commit unasked.
# Exit 4: the branch has a PR that is MERGED or CLOSED, and the PR's head is in this branch's
#   history. A push would never reach the base branch. A PR from an older branch that reused the
#   name does not count. Nothing is staged or pushed. For MERGED, stderr prints the commands that
#   move only the post-merge commits onto a new branch off the base. For CLOSED, it says to reopen
#   the PR (gh pr reopen) or start a new branch from HEAD.
# Exit 5: gh could not read the PR state, for example on an auth failure. Nothing is staged or
#   pushed. Fix gh (gh auth status) and rerun.
# Exit 6: the commit and the push are done, but the PR step failed. That step is the PR lookup
#   after the push, gh pr edit or gh pr create. It also fails when the PR became MERGED or CLOSED
#   during the push. Do not create a new branch. Fix gh and rerun to open or update the PR. After
#   a MERGED or CLOSED exit 6, the rerun ends in exit 4: follow that recovery.

set -euo pipefail

COMMIT_MSG=""
PR_TITLE=""
PR_BODY=""
CLOSES_ISSUE=""
JIRA_URL=""
ADD=()
BASELINE=""
LEAVE_UNTRACKED=0
COMMIT_ONLY=0

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
        --commit-only)  COMMIT_ONLY=1;     shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

REQUIRED=(COMMIT_MSG)
[[ "$COMMIT_ONLY" -eq 1 ]] || REQUIRED+=(PR_TITLE PR_BODY)
for VAR in "${REQUIRED[@]}"; do
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

SESSION_UNTRACKED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-untracked.sh"
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

# gh pr view exits 1 both for "no PR" and for a failed call, so it cannot tell them apart.
# gh pr list exits 0 with no output when the branch has no PR. It prints one line per PR, open
# ones first.
pr_lookup() {
    gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state all --json state,url,headRefOid,baseRefName \
        -q '(map(select(.state == "OPEN")) + map(select(.state != "OPEN")))[] | [.state, .url, .headRefOid, .baseRefName] | join(" ")'
}

# Prints the first PR that belongs to this branch, or nothing. A MERGED or CLOSED PR belongs to it
# only when its head is in this branch's history. Otherwise it came from an older branch that
# reused the name.
pick_pr() {
    local lines state url head base
    lines=$(pr_lookup) || return 1
    while read -r state url head base; do
        [[ -n "$state" ]] || continue
        if [[ "$state" == OPEN ]] || git merge-base --is-ancestor "$head" HEAD 2>/dev/null; then
            printf '%s %s %s %s' "$state" "$url" "$head" "$base"
            return 0
        fi
    done <<<"$lines"
}

PR_INFO=""
if [[ "$COMMIT_ONLY" -eq 0 ]]; then
    if ! PR_INFO=$(pick_pr); then
        echo "Error: could not read the PR state for this branch. Nothing was staged or pushed. Check gh (gh auth status) and rerun." >&2
        exit 5
    fi
fi
read -r PR_STATE PR_URL PR_HEAD PR_BASE <<<"$PR_INFO" || true
# A squash or rebase merge leaves the PR's commits out of the base's history, so a branch from
# HEAD would ship them again. Only the commits after the merged head move onto the base.
if [[ "$PR_STATE" == MERGED ]]; then
    {
        echo "Error: the PR for this branch is MERGED ($PR_URL). Nothing was staged or pushed."
        echo "Move the commits made after the merge, and any uncommitted edits, to a new branch off the base, then rerun:"
        echo "  git fetch origin $PR_BASE"
        echo "  git checkout -b $(git rev-parse --abbrev-ref HEAD)-followup"
        echo "  git rebase --autostash --onto origin/$PR_BASE $PR_HEAD"
    } >&2
    exit 4
fi
if [[ "$PR_STATE" == CLOSED ]]; then
    echo "Error: the PR for this branch is CLOSED without a merge ($PR_URL). Nothing was staged or pushed. Reopen it (gh pr reopen), or start a new branch from HEAD, then rerun." >&2
    exit 4
fi

in_list() {
    local f="$1" a; shift
    for a in "$@"; do
        [[ "$f" == "$a" || "$f" == "${a%/}/"* ]] && return 0
    done
    return 1
}
if [[ -n "$BASELINE" && ! -f "$BASELINE" ]]; then
    echo "Note: baseline $BASELINE not found; every untracked file needs --add." >&2
    BASELINE=""
fi
NEW=()
if [[ -n "$BASELINE" ]]; then
    while IFS= read -r -d '' F; do NEW+=("$F"); done < <(bash "$SESSION_UNTRACKED" --baseline "$BASELINE" 2>/dev/null)
fi

# .bf/ holds workflow artifacts, never part of the change, except .bf/conventions/ (the project
# convention tier, which is shared through the repo). An exclude pathspec cannot be re-included,
# so that tier is staged on its own.
STAGE=(${NAMED[@]+"${NAMED[@]}"})
STRAY=()
while IFS= read -r -d '' F; do
    in_list "$F" ${NAMED[@]+"${NAMED[@]}"} && continue
    if in_list "$F" ${NEW[@]+"${NEW[@]}"}; then
        STAGE+=("$F")
    else
        STRAY+=("$F")
    fi
done < <(bash "$SESSION_UNTRACKED")
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
[[ "$COMMIT_ONLY" -eq 0 ]] || exit 0

git push -u origin HEAD

pushed_pr_failed() {
    echo "Error: the branch is pushed, but the PR step failed: $1. Check gh (gh auth status), then rerun or open the PR by hand." >&2
    exit 6
}
# A PR can be opened or merged while the push runs, so the edit-or-create choice uses a fresh read.
PR_INFO=$(pick_pr) || pushed_pr_failed "could not read the PR state"
read -r PR_STATE PR_URL _ <<<"$PR_INFO" || true
case "$PR_STATE" in
    OPEN)
        gh pr edit --title "$PR_TITLE" --body "$BODY" || pushed_pr_failed "gh pr edit failed" ;;
    "")
        PR_URL=$(gh pr create --title "$PR_TITLE" --body "$BODY") || pushed_pr_failed "gh pr create failed" ;;
    *)
        pushed_pr_failed "the PR for this branch became $PR_STATE ($PR_URL)" ;;
esac
echo "$PR_URL"
