#!/usr/bin/env bash
# Deterministic merge, resolve and analyze steps of bf:bug-hunt. Emits one JSON object and writes it to the run dir.
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
#     resolve alone decides which verdicts survive (confirmed, refined, pre-existing). It sets
#     surviving:true|false on every finding and counts.surviving. Later steps read that flag.
#   findings.sh analyze <run_dir>
#     Validates <run_dir>/analysis.json against final.json and writes <run_dir>/analyzed.json.
#     analysis.json: {groups:[{id:"G1", kind:"duplicate|root-cause|pattern", title, root_cause,
#       fix_direction, members:[F ids], locations:["file:line"], keep:<F id, duplicate only>,
#       suspects:[{location, note}] (pattern only, optional)}],
#       links:[{from, to, note, order:"before|together"}]} with from/to a G id or an F id.
#     Valid when: every member is a surviving finding (surviving:true in final.json), each group
#     has >= 2 members, no finding is in two groups, a duplicate group names a kept member, link
#     endpoints exist and are not folded. Invalid input exits 1 with {error:"invalid_analysis", detail}.
#     analyzed.json is final.json plus: groups (each with severity = max member severity and folded
#     ids), links, per finding group / folded_into / also_reported_as, counts.groups, counts.folded.
#     A member with no severity counts as low.
set -uo pipefail

die() {
  if command -v jq >/dev/null; then jq -nc --arg e "$1" --arg d "$2" '{error: $e, detail: $d}'
  else printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; fi
  exit 1
}
command -v jq >/dev/null || die no_jq "jq is required"
RANK='def rank: {"critical":0,"high":1,"medium":2,"low":3}[. // "low"] // 3;'
cmd="${1:-}"; run_dir="${2:-}"
[ -n "$run_dir" ] && [ -d "$run_dir" ] || die bad_run_dir "usage: findings.sh merge|resolve|analyze <run_dir>"

merge() {
  local max="${1:-6}" valid=() invalid=() f
  for f in "$run_dir"/hunters/*.json; do
    [ -e "$f" ] || continue
    if jq -e 'type == "object"' "$f" >/dev/null 2>&1; then valid+=("$f"); else invalid+=("$(basename "$f" .json)"); fi
  done
  local invalid_json='[]'
  [ "${#invalid[@]}" -gt 0 ] && invalid_json=$(printf '%s\n' "${invalid[@]}" | jq -R . | jq -sc .)
  { [ "${#valid[@]}" -gt 0 ] && jq -s . "${valid[@]}" || echo '[]'; } | jq --argjson max "$max" --argjson invalid "$invalid_json" "$RANK"'
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
    | .findings |= map(. + {surviving: (.verdict | IN("confirmed", "refined", "pre-existing"))})
    | .failed_batches = [.batches[] | select(.id as $b | $done | index($b) | not) | .id]
    | .counts += (.findings | group_by(.verdict) | map({key: .[0].verdict, value: length}) | from_entries)
    | .counts.surviving = ([.findings[] | select(.surviving)] | length)
  ' "$run_dir/merged.json" > "$run_dir/final.json" || die resolve_failed "jq could not join verdicts"
  cat "$run_dir/final.json"
}

analyze() {
  [ -f "$run_dir/final.json" ] || die no_final "run findings.sh resolve first"
  [ -f "$run_dir/analysis.json" ] || die no_analysis "analysis.json is missing"
  jq -e 'type == "object"' "$run_dir/analysis.json" >/dev/null 2>&1 || die invalid_analysis "analysis.json is not a JSON object"
  local out
  out=$(jq --slurpfile a "$run_dir/analysis.json" "$RANK"'
    def text: type == "string" and length > 0;
    ($a[0].groups // []) as $gs | ($a[0].links // []) as $ls
    | (.findings | map({key: .id, value: .}) | from_entries) as $by
    | [.findings[] | select(.surviving) | .id] as $live
    | [$gs[] | .id] as $gids
    | ([$gs[] | select(.kind == "duplicate") | .keep as $k | ((.members // []) - [$k])[]
        | {key: tostring, value: $k}] | from_entries) as $into
    | ($into | keys) as $folded
    | [ ($gs[] | select(((.id // "") | test("^G[0-9]+$")) | not) | "bad group id \(.id)"),
        ($gids | group_by(.)[] | select(length > 1) | "duplicate group id \(.[0])"),
        ($gs[] | . as $g | (
          (select(["duplicate","root-cause","pattern"] | index($g.kind) | not) | "\($g.id): bad kind \($g.kind)"),
          (select(((.members // []) | length) < 2) | "\($g.id): needs >= 2 members"),
          ((.members // [])[] | . as $m | select($live | index($m) | not) | "\($g.id): \($m) is not a surviving finding"),
          ((.members // []) | group_by(.)[] | select(length > 1) | "\($g.id): \(.[0]) is listed twice in \($g.id)"),
          (select(.kind == "duplicate" and ((.members // []) | index($g.keep) | not)) | "\($g.id): keep must be a member"),
          (["title","root_cause","fix_direction"][] | select($g[.] | text | not) | "\($g.id): missing \(.)"))),
        ([$gs[] | (.members // []) | unique[]] | group_by(.)[] | select(length > 1) | "\(.[0]) is in more than one group"),
        ($ls[] | . as $l | (
          (["from","to"][] | . as $e | select(($gids + $live) | index($l[$e]) | not) | "link \($e) \($l[$e]) does not exist"),
          (["from","to"][] | . as $e | select($folded | index($l[$e])) | "link \($e) \($l[$e]) is a folded duplicate"),
          (select(.from == .to) | "link joins \(.from) to itself"),
          (select(["before","together"] | index($l.order) | not) | "link \(.from)->\(.to): bad order \($l.order)"),
          (select(.note | text | not) | "link \(.from)->\(.to): missing note"))) ] as $errs
    | if ($errs | length) > 0 then {error: "invalid_analysis", detail: ($errs | join("; "))}
      else
        ([$gs[] | .id as $g | (.members[] | {key: ., value: $g})] | from_entries) as $grp
        | .findings |= map(. as $f
            | . + {group: ($grp[$f.id] // null)}
            + (if $into[$f.id] then {folded_into: $into[$f.id]} else {} end)
            + ([$into | to_entries[] | select(.value == $f.id) | $by[.key] | {id, file, line}] as $also
               | if ($also | length) > 0 then {also_reported_as: $also} else {} end))
        | .groups = [$gs[] | . + {severity: ([.members[] | $by[.].severity // "low"] | min_by(rank)),
                                  folded: [.members[] | select($into[.])]}]
        | .links = $ls
        | .counts += {groups: ($gs | length), folded: ($folded | length)}
      end' "$run_dir/final.json") || die analyze_failed "jq could not apply analysis.json"
  if jq -e 'has("error")' <<< "$out" >/dev/null; then die "$(jq -r .error <<< "$out")" "$(jq -r .detail <<< "$out")"; fi
  echo "$out" > "$run_dir/analyzed.json"
  cat "$run_dir/analyzed.json"
}

case "$cmd" in
  merge) merge "${3:-6}" ;;
  resolve) resolve ;;
  analyze) analyze ;;
  *) die bad_command "usage: findings.sh merge|resolve|analyze <run_dir>" ;;
esac
