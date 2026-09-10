#!/usr/bin/env bash
# Fetch every actionable comment on a PR as one JSON payload.
#
# Usage: fetch-pr-comments.sh [<pr-number> | <pr-url> | --all]
#   no arg   -> PR for the current branch
#   --all    -> include already-resolved threads and threads we already answered
#
# Output (stdout, single JSON object):
#   {pr, url, title, head_sha, viewer, base, threads[], notes[], counts{}}
#     threads[] = {kind, thread_id, comment_id, file, line, side, outdated,
#                  resolved, author, is_bot, body, replies[], diff_hunk,
#                  answered_by_viewer}
#     files[]   = {path, additions, deletions, change_type} — the PR's changed files,
#                 DELETED ones excluded; this is the search surface for sibling instances
#       kind: "thread" (line-anchored, resolvable) | "issue" (PR-level) | "review" (review summary body)
#   notes[] = human-readable lines about what was filtered and why
# Errors: {"error":"<code>","detail":"..."} + exit 1
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }

command -v gh  >/dev/null 2>&1 || die gh_missing "gh CLI not installed"
command -v jq  >/dev/null 2>&1 || die jq_missing "jq not installed"
gh auth status >/dev/null 2>&1 || die gh_unauthenticated "run: gh auth login"

INCLUDE_ALL=false
ARG=""
for a in "$@"; do
  case "$a" in
    --all) INCLUDE_ALL=true ;;
    ""|--*) ;;
    *) ARG="$a" ;;
  esac
done

# Resolve owner/repo/number -------------------------------------------------
if [[ "$ARG" =~ ^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; NUM="${BASH_REMATCH[3]}"
else
  NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
    || die no_repo "not a GitHub repo, or gh cannot see it"
  OWNER="${NWO%%/*}"; REPO="${NWO##*/}"
  if [[ "$ARG" =~ ^#?([0-9]+)$ ]]; then
    NUM="${BASH_REMATCH[1]}"
  else
    NUM=$(gh pr view --json number -q .number 2>/dev/null) \
      || die no_pr "no PR found for the current branch; pass a PR number or URL"
  fi
fi

RAW=$(gh api graphql -F owner="$OWNER" -F repo="$REPO" -F num="$NUM" -f query='
query($owner:String!,$repo:String!,$num:Int!){
  viewer{login}
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      number url title
      baseRefName headRefName
      commits(last:1){nodes{commit{oid}}}
      files(first:100){totalCount nodes{path additions deletions changeType}}
      comments(first:100){nodes{
        author{login __typename} body createdAt
      }}
      reviews(first:100){nodes{
        author{login __typename} body state submittedAt
      }}
      reviewThreads(first:100){nodes{
        id isResolved isOutdated path line originalLine diffSide
        comments(first:50){nodes{
          databaseId author{login __typename} body createdAt diffHunk
        }}
      }}
    }
  }
}' 2>&1) || {
  DETAIL=$(printf '%s' "$RAW" | tr -d '\n' | head -c 400 | sed 's/"/\\"/g')
  case "$RAW" in
    *"Could not resolve to a PullRequest"*|*NOT_FOUND*) die pr_not_found "no PR #$NUM in $OWNER/$REPO" ;;
    *) die graphql_failed "$DETAIL" ;;
  esac
}

printf '%s' "$RAW" | jq -e '.data.repository.pullRequest' >/dev/null 2>&1 \
  || die pr_not_found "no PR #$NUM in $OWNER/$REPO"

printf '%s' "$RAW" | jq --argjson all "$INCLUDE_ALL" '
  .data as $d
  | $d.viewer.login as $me
  | $d.repository.pullRequest as $pr

  # a thread/comment we already replied to is done unless --all
  | def answered($authors): ($authors | index($me)) != null;

  ( [ $pr.reviewThreads.nodes[]
      | (.comments.nodes // []) as $cs
      | ($cs[0] // {}) as $first
      | {
          kind: "thread",
          thread_id: .id,
          comment_id: ($first.databaseId // null),
          file: .path,
          line: (.line // .originalLine),
          side: (.diffSide // "RIGHT"),
          outdated: (.isOutdated // false),
          resolved: (.isResolved // false),
          author: ($first.author.login // "unknown"),
          is_bot: (($first.author.__typename // "") == "Bot"),
          body: ($first.body // ""),
          replies: [ $cs[1:][] | {author: (.author.login // "unknown"), body: .body} ],
          diff_hunk: ($first.diffHunk // ""),
          answered_by_viewer: answered([ $cs[1:][] | .author.login ])
        } ] ) as $threads

  | ( [ $pr.comments.nodes[]
        | select((.body // "") | test("\\S"))
        | {
            kind: "issue",
            thread_id: null, comment_id: null,
            file: null, line: null, side: null,
            outdated: false, resolved: false,
            author: (.author.login // "unknown"),
            is_bot: ((.author.__typename // "") == "Bot"),
            body: .body, replies: [], diff_hunk: "",
            answered_by_viewer: false
          } ] ) as $issues

  | ( [ $pr.reviews.nodes[]
        | select((.body // "") | test("\\S"))
        | select((.author.login // "") != $me)
        | {
            kind: "review",
            thread_id: null, comment_id: null,
            file: null, line: null, side: null,
            outdated: false, resolved: false,
            author: (.author.login // "unknown"),
            is_bot: ((.author.__typename // "") == "Bot"),
            body: .body, replies: [], diff_hunk: "",
            answered_by_viewer: false,
            state: .state
          } ] ) as $reviews

  | ( [ ($pr.files.nodes // [])[]
        | select(.changeType != "DELETED")
        | {path: .path, additions: .additions, deletions: .deletions, change_type: .changeType} ] ) as $files

  | ($threads + $issues + $reviews) as $every
  | ( if $all then $every
      else [ $every[] | select(.resolved == false and .answered_by_viewer == false) ]
      end ) as $open

  | {
      pr: $pr.number,
      url: $pr.url,
      title: $pr.title,
      head_sha: ($pr.commits.nodes[0].commit.oid // null),
      viewer: $me,
      base: $pr.baseRefName,
      head: $pr.headRefName,
      threads: $open,
      files: $files,
      counts: {
        files: ($files | length),
        files_deleted: ((($pr.files.nodes // []) | map(select(.changeType == "DELETED")) | length)),
        files_truncated: ((($pr.files.totalCount // 0) > 100)),
        total: ($every | length),
        actionable: ($open | length),
        resolved: ([ $every[] | select(.resolved) ] | length),
        already_answered: ([ $every[] | select(.answered_by_viewer) ] | length),
        outdated: ([ $open[] | select(.outdated) ] | length),
        bot: ([ $open[] | select(.is_bot) ] | length)
      },
      notes: (
        [ ( ([ $every[] | select(.resolved) ] | length) as $r
            | if ($r > 0 and ($all|not)) then "\($r) resolved thread(s) skipped — rerun with --all to include" else empty end ),
          ( ([ $every[] | select(.answered_by_viewer) ] | length) as $a
            | if ($a > 0 and ($all|not)) then "\($a) thread(s) already answered by \($me) skipped — rerun with --all to include" else empty end ),
          ( ([ $open[] | select(.outdated) ] | length) as $o
            | if $o > 0 then "\($o) actionable thread(s) are outdated — the code they point at has moved" else empty end ),
          ( if (($pr.files.totalCount // 0) > 100)
            then "PR touches \($pr.files.totalCount) files; only the first 100 are listed — the sibling-instance search surface is incomplete"
            else empty end ) ]
      )
    }'
