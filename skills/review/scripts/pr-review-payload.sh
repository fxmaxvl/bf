#!/usr/bin/env bash
# Build the payload for one GitHub PR review from bf:review findings, keeping inline comments to
# lines the PR diff shows. GitHub rejects the whole review when one comment points outside the diff.
#
# Usage: pr-review-payload.sh <findings.json> <diff_file> <commit_sha> <COMMENT|REQUEST_CHANGES>
#
# findings.json is a JSON array, one entry per finding:
#   [{"id":"C1","label":"critical","path":"src/a.ts","line":42,"text":"<problem>. Suggested: <fix>"},
#    {"id":"X1","label":"must-fix","path":"src/b.ts","line":"10-14","text":"..."},
#    {"id":"Y1","label":"should-consider","path":null,"line":null,"text":"..."}]
#   "line" is a number, a "start-end" range, or null.
#
# Output: {commit_id, event, body, comments:[{path, line, side:"RIGHT", body}]}, ready for
#   gh api repos/<owner>/<repo>/pulls/<n>/reviews --input <file>
# A finding goes inline when its line is a context or added line of the diff. A range goes inline,
# anchored on its last line with start_line, only when both ends are in the same hunk. Every
# other finding is listed in the review body.
# Errors: {"error":...,"detail":...} + exit 1 — usage, jq_missing, no_findings, no_diff, bad_event.
set -euo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }

command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"
[ $# -eq 4 ] || die usage "pr-review-payload.sh <findings.json> <diff_file> <commit_sha> <COMMENT|REQUEST_CHANGES>"
findings=$1; diff_file=$2; sha=$3; event=$4
jq -e 'type == "array"' "$findings" >/dev/null 2>&1 || die no_findings "findings must be a JSON array: $findings"
[ -f "$diff_file" ] || die no_diff "diff file not found: $diff_file"
case "$event" in COMMENT|REQUEST_CHANGES) ;; *) die bad_event "event must be COMMENT or REQUEST_CHANGES" ;; esac

# Emits "<path>\t<new-side line>\t<hunk index>" for every line a review comment can target.
# File headers are read only between "diff --git" and the first "@@", so a removed line whose text
# starts with "-- " is never taken for a header.
anchors=$(awk -F '\t' '
  /^diff --git / { path = ""; header = 1; next }
  header && /^\+\+\+ / { p = substr($0, 5); sub(/^b\//, "", p); path = (p == "/dev/null") ? "" : p; next }
  /^@@ / { header = 0; hunk++; split($0, h, " "); split(substr(h[3], 2), n, ","); line = n[1] + 0; next }
  header || path == "" { next }
  /^[ +]/ { printf "%s\t%d\t%d\n", path, line, hunk; line++ }
' "$diff_file" | jq -Rn '[inputs | split("\t") | {key: (.[0] + ":" + .[1]), value: (.[2] | tonumber)}] | from_entries')

jq --argjson a "$anchors" --arg sha "$sha" --arg event "$event" '
  def fmt: "**\(.id)** [\(.label)] \(.text)";
  def ends: (.line | tostring | split("-") | map(tonumber? // empty));
  def place:
    (ends) as $e
    | if .path == null or ($e | length) == 0 then null
      else ($a["\(.path):\($e[0])"]) as $h1 | ($a["\(.path):\($e[-1])"]) as $h2
        | if $h1 == null or $h2 == null or $h1 != $h2 then null
          elif $e[0] == $e[-1] then {path, line: $e[0], side: "RIGHT", body: fmt}
          else {path, start_line: $e[0], start_side: "RIGHT", line: $e[-1], side: "RIGHT", body: fmt} end
      end;
  [.[] | {f: ., c: place}] as $all
  | ($all | map(select(.c == null) | .f)) as $rest
  | {commit_id: $sha, event: $event,
     body: (["bf:review: \(length) finding(s), \($all | map(select(.c != null)) | length) inline."]
            + (if ($rest | length) > 0 then ["", "Outside the diff:"]
                 + ($rest | map("- " + fmt + (if .path then " (`\(.path)\(if .line then ":\(.line)" else "" end)`)" else "" end)))
               else [] end)
            | join("\n")),
     comments: ($all | map(.c | select(. != null)))}
' "$findings"
