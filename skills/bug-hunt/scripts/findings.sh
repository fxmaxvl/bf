#!/usr/bin/env bash
# Deterministic merge and resolve steps of bf:bug-hunt. Emits one JSON object and writes it to the run dir.
#
# Usage:
#   findings.sh merge <run_dir> [max_batches]
#     Reads <run_dir>/hunters/*.json ({hunter_id, lens, findings:[{file,line,end_line,severity,title,
#     why,repro_hint}]}) and writes <run_dir>/merged.json:
#       findings: clusters anchored on their first line — a finding joins a cluster when it is in the
#                 same file and at most 2 lines below the anchor, so clusters never chain past ±2.
#                 sources counts distinct hunter_id, never lenses. Nothing is dropped.
#       batches:  directory groups packed into at most max_batches (default 6) by repeatedly merging
#                 the lexically adjacent pair with the fewest findings, so neighbours merge first.
#       invalid:  hunter files that were not valid JSON (their lens is a coverage gap).
#   findings.sh resolve <run_dir>
#     Joins <run_dir>/verifiers/<batch_id>.json ({batch_id, verdicts:[{id, verdict, severity?,
#     file?, line?, title?, note}]}) onto merged.json and writes <run_dir>/final.json. A finding
#     with no verdict — its batch failed or the verifier skipped it — gets verdict "unverified".
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; exit 1; }
command -v jq >/dev/null || die no_jq "jq is required"
cmd="${1:-}"; run_dir="${2:-}"
[ -n "$run_dir" ] && [ -d "$run_dir" ] || die bad_run_dir "usage: findings.sh merge|resolve <run_dir>"

merge() {
  local max="${1:-6}" valid=() invalid=() f
  for f in "$run_dir"/hunters/*.json; do
    [ -e "$f" ] || continue
    if jq -e 'type == "object"' "$f" >/dev/null 2>&1; then valid+=("$f"); else invalid+=("$(basename "$f" .json)"); fi
  done
  local invalid_json='[]'
  [ "${#invalid[@]}" -gt 0 ] && invalid_json=$(printf '%s\n' "${invalid[@]}" | jq -R . | jq -sc .)
  { [ "${#valid[@]}" -gt 0 ] && jq -s . "${valid[@]}" || echo '[]'; } | jq --argjson max "$max" --argjson invalid "$invalid_json" '
    def rank: {"critical":0,"high":1,"medium":2,"low":3}[. // "low"] // 3;
    def dir: if (.file // "") == "" then "(unlocated)"
             else (.file | split("/") | .[:-1] | join("/")) | if . == "" then "." else . end end;
    def pack($k): if length <= $k then . else
        ([range(0; length - 1) as $i | {i: $i, s: ((.[$i].ids | length) + (.[$i + 1].ids | length))}]
         | min_by(.s).i) as $i
        | (.[:$i] + [{dirs: (.[$i].dirs + .[$i + 1].dirs), ids: (.[$i].ids + .[$i + 1].ids)}] + .[$i + 2:])
        | pack($k) end;
    [ .[] | . as $h | ($h.findings // [])[]
      | . + {hunter_id: ($h.hunter_id // "unknown"), lens: ($h.lens // "unknown"),
             line: ((.line // 0) | tonumber? // 0)} ]
    | sort_by(.file // "", .line)
    | reduce .[] as $f ([];
        if length > 0 and (.[-1].file == ($f.file // "")) and ($f.file // "") != ""
           and ($f.line - .[-1].line) <= 2
        then .[-1].members += [$f]
        else . + [{file: ($f.file // ""), line: $f.line, members: [$f]}] end)
    | map(. as $c | ($c.members | min_by(.severity | rank)) as $top
          | {file, line,
             end_line: ([$c.members[] | (.end_line // .line) | tonumber? // 0] + [$c.line] | max),
             severity: ($top.severity // "low"), title: $top.title, why: $top.why, repro_hint: $top.repro_hint,
             hunters: ([$c.members[].hunter_id] | unique), lenses: ([$c.members[].lens] | unique),
             members: $c.members}
          | . + {sources: (.hunters | length)})
    | sort_by((.severity | rank), -.sources, .file, .line)
    | to_entries | map(.value + {id: "F\(.key + 1)"})
    | . as $all
    | {findings: $all,
       batches: ($all | group_by(dir) | map({dirs: [.[0] | dir], ids: map(.id)})
                 | sort_by(.dirs[0]) | pack($max)
                 | to_entries | map({id: "B\(.key + 1)", dirs: .value.dirs, finding_ids: .value.ids})),
       invalid: $invalid,
       counts: {findings: ($all | length), corroborated: ([$all[] | select(.sources > 1)] | length)}}
  ' > "$run_dir/merged.json" || die merge_failed "jq could not merge hunter output"
  cat "$run_dir/merged.json"
}

resolve() {
  [ -f "$run_dir/merged.json" ] || die no_merge "run findings.sh merge first"
  local v
  v=$(for f in "$run_dir"/verifiers/*.json; do [ -e "$f" ] && jq -c 'select(type == "object")' "$f" 2>/dev/null; done | jq -sc .)
  jq --argjson v "$v" '
    ([$v[] | (.verdicts // [])[] | {key: .id, value: .}] | from_entries) as $by
    | ([$v[] | .batch_id] ) as $done
    | .findings |= map(. as $f | ($by[$f.id] // null) as $r
        | if $r == null then . + {verdict: "unverified"}
          else . + {verdict: $r.verdict, note: $r.note}
               + ({severity: $r.severity, file: $r.file, line: $r.line, title: $r.title}
                  | with_entries(select(.value != null))) end)
    | .failed_batches = [.batches[] | select(.id as $b | $done | index($b) | not) | .id]
    | .counts += (.findings | group_by(.verdict) | map({key: .[0].verdict, value: length}) | from_entries)
  ' "$run_dir/merged.json" > "$run_dir/final.json" || die resolve_failed "jq could not join verdicts"
  cat "$run_dir/final.json"
}

case "$cmd" in
  merge) merge "${3:-6}" ;;
  resolve) resolve ;;
  *) die bad_command "usage: findings.sh merge|resolve <run_dir>" ;;
esac
