#!/usr/bin/env bash
# Deterministic merge, resolve, analyze and timing steps of bf:bug-hunt. Emits one JSON object; merge, resolve
# and analyze also write it to the run dir.
#
# Usage:
#   findings.sh merge <run_dir> [max_batches]
#     Reads <run_dir>/hunters/*.json ({hunter_id, lens, findings:[{file,line,end_line,severity,title,
#     why,repro_hint}]}) and writes <run_dir>/merged.json:
#       findings: clusters anchored on their first line — a finding joins a cluster when it is in the
#                 same file and at most 2 lines below the anchor, so clusters never chain past ±2.
#                 sources counts distinct hunter_id, never lenses. Nothing is dropped. members are
#                 ordered by severity. The first gives the cluster its title and id (F3). The rest get
#                 member ids (F3.2, F3.3, …) so a verifier can split one out as a separate defect.
#       batches:  directory groups packed into at most max_batches (default 6) by repeatedly merging
#                 the lexically adjacent pair with the fewest findings, so neighbours merge first.
#       invalid:  hunter files that were not valid JSON (their lens is a coverage gap).
#       ignored:  valid hunter files whose hunter_id differs from the file name (e.g. hunters/x.retry.json);
#                 they add no findings.
#   findings.sh resolve <run_dir>
#     Joins <run_dir>/verifiers/<batch_id>.json ({batch_id, verdicts:[{id, verdict, severity?,
#     file?, line?, title?, note}]}), read only for batch ids in merged.json, onto merged.json and writes
#     <run_dir>/final.json; any other verifiers/*.json is appended to ignored and adds no verdicts. A finding
#     with no verdict — its batch failed or the verifier skipped it — gets verdict "unverified".
#     A verdict on a member id (F3.2) splits that member out as its own finding, placed after its
#     cluster with split_from: "F3"; the cluster's end_line, hunters, lenses and sources are rebuilt
#     from the members it keeps. counts.findings and counts.corroborated count after the split.
#     resolve alone decides which verdicts survive (confirmed, refined, pre-existing). It sets
#     surviving:true|false on every finding and counts.surviving. Later steps read that flag.
#   findings.sh analyze <run_dir>
#     Validates <run_dir>/analysis.json against final.json and writes <run_dir>/analyzed.json.
#     This header owns the validity rules; the analyst prompt in SKILL.md only gives the field shape.
#     analysis.json: {groups:[{id:"G1", kind:"duplicate|root-cause|pattern", title, root_cause,
#       fix_direction, members:[F ids], keep:<F id>, suspects:[{location, note}]}],
#       links:[{from, to, note, order:"before|together"}]}
#     Valid when all of these hold; any violation exits 1 with {error:"invalid_analysis", detail}:
#       shape:   groups and links are arrays of objects; ids, kind, keep, order, members, from and to are
#                strings (members an array of them); suspects, when present, an array of {location, note}.
#                A null keep or null or empty suspects counts as absent.
#       groups:  id matches G<number> and is unique; kind is one of the three; title, root_cause and
#                fix_direction are non-empty strings; >= 2 members; each member is a surviving finding
#                (surviving:true in final.json), listed once in its group and in no other group.
#       keep:    present only on a duplicate group, where it must be one of its members.
#       suspects: allowed only on a pattern group.
#       links:   from and to are an existing G id or surviving F id, not a folded duplicate, and differ;
#                order is before or together; note is a non-empty string.
#     analyzed.json is final.json plus: groups (each with severity = max member severity and folded
#     ids), links, per finding group / folded_into / also_reported_as, counts.groups, counts.folded.
#     A member with no severity counts as low. An empty analysis ({groups:[],links:[]}) is valid.
#   findings.sh mark <run_dir> <step> [label]
#     Appends {step, label, by:"agent", start, end} (epoch seconds, start = end) to <run_dir>/timing.jsonl
#     and prints it.
#   findings.sh timing <run_dir>
#     Summarizes timing.jsonl. hunt-init.sh, merge, resolve and analyze append their own rows (by:"script").
#     merge and resolve also add one "hunter" / "verifier" row per output file, timed by its mtime (whole
#     seconds): only hunters/<hunter_id>.json whose hunter_id matches its name, and verifiers/<batch_id>.json
#     for a batch in merged.json. Hunter durations run from the first "hunt" mark (else init), verifier
#     durations from the first "verify" mark (else merge), so a re-mark before a retry never makes one
#     negative; any other mark's from the row that ended before it. A rerun re-stamps the
#     same file: the last agent row per step and label wins.
#     Output: {wall, script, agent: wall - script, steps:[{step, label, by, at, duration}],
#     pipeline:{hunter_spread: last minus first hunter finish, verify_sum, verify_wall}}.
#     Seconds from the first row, rounded to 0.1. A missing anchor gives null, never an error.
set -uo pipefail

die() {
  if command -v jq >/dev/null; then jq -nc --arg e "$1" --arg d "$2" '{error: $e, detail: $d}'
  else printf '{"error":"%s","detail":"%s"}\n' "$1" "$2"; fi
  exit 1
}
command -v jq >/dev/null || die no_jq "jq is required"
row() { # step label by start [end]
  jq -nc --arg s "$1" --arg l "$2" --arg b "$3" --argjson a "$4" --argjson e "${5:-$4}" \
    '{step: $s, label: $l, by: $b, start: $a, end: $e}'
}
# A failed stamp never fails the step it times, and never writes to stdout.
stamp() { row "$@" >> "$run_dir/timing.jsonl" 2>/dev/null || true; }
now() { jq -n now; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
stamp_files() { # step subdir id... — only <id>.json files get a row, so a stray file is never an agent
  local step="$1" sub="$2" id; shift 2
  for id in "$@"; do [ -e "$run_dir/$sub/$id.json" ] && stamp "$step" "$id" agent "$(mtime "$run_dir/$sub/$id.json")"; done
}
RANK='def rank: {"critical":0,"high":1,"medium":2,"low":3}[. // "low"] // 3;'
# Shared by merge and resolve, so a cluster rebuilt after a split reads the same as one merge built.
# Input {file, line, members} with members already ordered by severity.
SUMMARIZE='def summarize: .members[0] as $top
  | . + {end_line: ([.members[] | (.end_line // .line) | tonumber? // 0] + [.line] | max),
         severity: ($top.severity // "low"), title: $top.title, why: $top.why, repro_hint: $top.repro_hint,
         hunters: ([.members[].hunter_id] | unique), lenses: ([.members[].lens] | unique)}
  | . + {sources: (.hunters | length)};'
cmd="${1:-}"; run_dir="${2:-}"
[ -n "$run_dir" ] && [ -d "$run_dir" ] || die bad_run_dir "usage: findings.sh merge|resolve|analyze|mark|timing <run_dir>"

merge() {
  local max="${1:-6}" valid=() invalid=() ignored=() hids=() f b t0
  t0=$(now)
  for f in "$run_dir"/hunters/*.json; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .json)
    if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then invalid+=("$b")
    elif jq -e --arg b "$b" '.hunter_id == $b' "$f" >/dev/null 2>&1; then valid+=("$f"); hids+=("$b")
    else ignored+=("hunters/$b.json"); fi
  done
  local invalid_json='[]' ignored_json='[]'
  [ "${#invalid[@]}" -gt 0 ] && invalid_json=$(printf '%s\n' "${invalid[@]}" | jq -R . | jq -sc .)
  [ "${#ignored[@]}" -gt 0 ] && ignored_json=$(printf '%s\n' "${ignored[@]}" | jq -R . | jq -sc .)
  { [ "${#valid[@]}" -gt 0 ] && jq -s . "${valid[@]}" || echo '[]'; } \
    | jq --argjson max "$max" --argjson invalid "$invalid_json" --argjson ignored "$ignored_json" "$RANK$SUMMARIZE"'
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
    | map(.members |= sort_by(.severity | rank) | summarize)
    | sort_by((.severity | rank), -.sources, .file, .line)
    | to_entries | map(.value + {id: "F\(.key + 1)"}
        | .id as $id | .members |= (to_entries | map(.value + {id: (if .key == 0 then $id else "\($id).\(.key + 1)" end)})))
    | . as $all
    | {findings: $all,
       batches: ($all | group_by(dir) | map({dirs: [.[0] | dir], ids: map(.id)})
                 | sort_by(.dirs[0]) | pack($max)
                 | to_entries | map({id: "B\(.key + 1)", dirs: .value.dirs, finding_ids: .value.ids})),
       invalid: $invalid, ignored: $ignored,
       counts: {findings: ($all | length), corroborated: ([$all[] | select(.sources > 1)] | length)}}
  ' > "$run_dir/merged.json" || die merge_failed "jq could not merge hunter output"
  stamp_files hunter hunters ${hids[@]+"${hids[@]}"}; stamp merge "" script "$t0" "$(now)"
  cat "$run_dir/merged.json"
}

resolve() {
  [ -f "$run_dir/merged.json" ] || die no_merge "run findings.sh merge first"
  local v ids ign t0
  t0=$(now)
  ids=$(jq -r '.batches[]?.id' "$run_dir/merged.json" 2>/dev/null)
  # Only <batch_id>.json for a batch in merged.json counts; its file name, not its content, marks the batch done.
  v=$(for b in $ids; do f="$run_dir/verifiers/$b.json"
        [ -e "$f" ] && jq -c --arg b "$b" 'select(type == "object") | .batch_id = $b' "$f" 2>/dev/null; done | jq -sc .)
  local known=" $(echo $ids) " stray=()
  for f in "$run_dir"/verifiers/*.json; do
    [ -e "$f" ] || continue
    case $known in *" $(basename "$f" .json) "*) ;; *) stray+=("verifiers/$(basename "$f")") ;; esac
  done
  ign='[]'
  [ "${#stray[@]}" -gt 0 ] && ign=$(printf '%s\n' "${stray[@]}" | jq -R . | jq -sc .)
  jq --argjson v "$v" --argjson ign "$ign" "$RANK$SUMMARIZE"'
    ([$v[] | (.verdicts // [])[] | {key: .id, value: .}] | from_entries) as $by
    | ([$v[] | .batch_id] ) as $done
    | .ignored = ((.ignored // []) + $ign)
    | .findings |= (map(. as $f | [($f.members // [])[1:][] | select($by[.id])] as $out
        | if ($out | length) == 0 then [$f]
          else [$f | .members -= $out | summarize]
               + [$out[] | {id, file: (.file // ""), line, members: [.], split_from: $f.id} | summarize] end)
        | add // [])
    | .findings |= map(. as $f | ($by[$f.id] // null) as $r
        | if $r == null then . + {verdict: "unverified"}
          else . + {verdict: $r.verdict, note: $r.note}
               + ({severity: $r.severity, file: $r.file, line: $r.line, title: $r.title}
                  | with_entries(select(.value != null))) end)
    | .findings |= map(. + {surviving: (.verdict | IN("confirmed", "refined", "pre-existing"))})
    | .failed_batches = [.batches[] | select(.id as $b | $done | index($b) | not) | .id]
    | .counts += (.findings | group_by(.verdict) | map({key: .[0].verdict, value: length}) | from_entries)
    | .counts.surviving = ([.findings[] | select(.surviving)] | length)
    | .counts.findings = (.findings | length)
    | .counts.corroborated = ([.findings[] | select(.sources > 1)] | length)
  ' "$run_dir/merged.json" > "$run_dir/final.json" || die resolve_failed "jq could not join verdicts"
  stamp_files verifier verifiers $ids; stamp resolve "" script "$t0" "$(now)"
  cat "$run_dir/final.json"
}

analyze() {
  [ -f "$run_dir/final.json" ] || die no_final "run findings.sh resolve first"
  [ -f "$run_dir/analysis.json" ] || die no_analysis "analysis.json is missing"
  jq -e 'type == "object"' "$run_dir/analysis.json" >/dev/null 2>&1 || die invalid_analysis "analysis.json is not a JSON object"
  local out t0
  t0=$(now)
  out=$(jq --slurpfile a "$run_dir/analysis.json" "$RANK"'
    def text: type == "string" and length > 0;
    def shape_errors($gs; $ls):
      if ($gs | type) != "array" then ["groups must be an array"]
      elif ($ls | type) != "array" then ["links must be an array"]
      else [ ($gs[] | select(type != "object") | "a group is not an object"),
             ($gs[] | select(type == "object") | . as $g | (
               (select((.id | type) != "string") | "a group id must be a string"),
               (select((.members | type) != "array" or any(.members[]; type != "string"))
                  | "\($g.id): members must be an array of strings"),
               (select((.kind | type) != "string") | "\($g.id): kind must be a string"),
               (select((.keep | type) | IN("null", "string") | not) | "\($g.id): keep must be a string"),
               (select((.suspects // []) | (type != "array")
                  or any(.[]; type != "object" or (.location | text | not) or (.note | text | not)))
                  | "\($g.id): suspects must be an array of {location, note}"))),
             ($ls[] | select(type != "object") | "a link is not an object"),
             ($ls[] | select(type == "object" and ((.from | type) != "string" or (.to | type) != "string"))
                | "a link from and to must be strings"),
             ($ls[] | select(type == "object" and (.order | type) != "string") | "a link order must be a string") ]
      end;
    def errors($gs; $ls; $live; $gids; $folded):
      [ ($gs[] | select(((.id) | test("^G[0-9]+$")) | not) | "bad group id \(.id)"),
        ($gids | group_by(.)[] | select(length > 1) | "duplicate group id \(.[0])"),
        ($gs[] | . as $g | (
          (select($g.kind | IN("duplicate","root-cause","pattern") | not) | "\($g.id): bad kind \($g.kind)"),
          (select(.members | length < 2) | "\($g.id): needs >= 2 members"),
          (.members[] | . as $m | select($live | index($m) | not) | "\($g.id): \($m) is not a surviving finding"),
          (.members | group_by(.)[] | select(length > 1) | "\($g.id): \(.[0]) is listed twice in \($g.id)"),
          (select(.kind == "duplicate" and (.members | any(. == $g.keep) | not)) | "\($g.id): keep must be a member"),
          (select(.kind != "duplicate" and .keep != null) | "\($g.id): keep is only for duplicate groups"),
          (select(.kind != "pattern" and ((.suspects // []) | length) > 0) | "\($g.id): suspects are only for pattern groups"),
          (["title","root_cause","fix_direction"][] | select($g[.] | text | not) | "\($g.id): missing \(.)"))),
        ([$gs[] | .members | unique[]] | group_by(.)[] | select(length > 1) | "\(.[0]) is in more than one group"),
        ($ls[] | . as $l | (
          (["from","to"][] | . as $e | select(($gids + $live) | index($l[$e]) | not) | "link \($e) \($l[$e]) does not exist"),
          (["from","to"][] | . as $e | select($folded | index($l[$e])) | "link \($e) \($l[$e]) is a folded duplicate"),
          (select(.from == .to) | "link joins \(.from) to itself"),
          (select($l.order | IN("before","together") | not) | "link \(.from)->\(.to): bad order \($l.order)"),
          (select(.note | text | not) | "link \(.from)->\(.to): missing note"))) ];
    def apply($gs; $ls; $into):
      (.findings | map({key: .id, value: .}) | from_entries) as $by
      | ([$gs[] | .id as $g | (.members[] | {key: ., value: $g})] | from_entries) as $grp
      | .findings |= map(. as $f
          | . + {group: ($grp[$f.id] // null)}
          + (if $into[$f.id] then {folded_into: $into[$f.id]} else {} end)
          + ([$into | to_entries[] | select(.value == $f.id) | $by[.key] | {id, file, line}] as $also
             | if ($also | length) > 0 then {also_reported_as: $also} else {} end))
      | .groups = [$gs[] | . + {severity: ([.members[] | $by[.].severity // "low"] | min_by(rank)),
                                folded: [.members[] | select($into[.])]}]
      | .links = $ls
      | .counts += {groups: ($gs | length), folded: ($into | length)};
    ($a[0].groups // []) as $gs | ($a[0].links // []) as $ls
    | (shape_errors($gs; $ls)) as $bad
    | if ($bad | length) > 0 then {error: "invalid_analysis", detail: ($bad | join("; "))}
      else
        [.findings[] | select(.surviving) | .id] as $live
        | [$gs[] | .id] as $gids
        | ([$gs[] | select(.kind == "duplicate" and (.keep as $k | .members | any(. == $k))) | .keep as $k | (.members - [$k])[]
            | {key: ., value: $k}] | from_entries) as $into
        | errors($gs; $ls; $live; $gids; $into | keys) as $errs
        | if ($errs | length) > 0 then {error: "invalid_analysis", detail: ($errs | join("; "))}
          else apply($gs; $ls; $into) end
      end' "$run_dir/final.json" 2>/dev/null) || die analyze_failed "jq could not apply analysis.json"
  if jq -e 'has("error")' <<< "$out" >/dev/null; then die "$(jq -r .error <<< "$out")" "$(jq -r .detail <<< "$out")"; fi
  echo "$out" > "$run_dir/analyzed.json"
  stamp analyze "" script "$t0" "$(now)"
  cat "$run_dir/analyzed.json"
}

mark() {
  [ -n "${1:-}" ] || die missing_step "usage: findings.sh mark <run_dir> <step> [label]"
  local r
  r=$(row "$1" "${2:-}" agent "$(now)") && echo "$r" >> "$run_dir/timing.jsonl" || die mark_failed "cannot append to timing.jsonl"
  echo "$r"
}

timing() {
  [ -s "$run_dir/timing.jsonl" ] || die no_timing "timing.jsonl is missing or empty"
  jq -sc '
    def r1: if . == null then null else (. * 10 + 0.5 | floor) / 10 end;
    def mark($s): [.[] | select(.step == $s) | .end] | if length > 0 then .[-1] else null end;
    def first_mark($s): [.[] | select(.step == $s) | .end] | if length > 0 then .[0] else null end;
    def since($a): if $a == null then null else .end - $a end;
    map(select(type == "object" and (.start | type) == "number" and (.end | type) == "number"))
    | . as $all | (map(.start) | min) as $t0 | (map(.end) | max) as $t1
    | (first_mark("hunt") // mark("init")) as $hs | (first_mark("verify") // mark("merge")) as $vs
    | [.[] | select(.by == "script")] as $script
    | (map(select(.by == "agent")) | group_by([.step, .label]) | map(.[-1])) as $agent
    | [$agent[] | select(.step == "hunter")] as $h | [$agent[] | select(.step == "verifier")] as $v
    | ([$script[] | .end - .start] | add // 0) as $script_s
    | [ ($script[] | {step, label, by, at: (.start - $t0), duration: (.end - .start)}),
        ($h[] | {step, label, by, at: (.end - $t0), duration: since($hs)}),
        ($v[] | {step, label, by, at: (.end - $t0), duration: since($vs)}),
        ($agent[] | select(.step | IN("hunter", "verifier") | not) | . as $m
         | {step, label, by, at: (.end - $t0),
            duration: ([$all[] | .end | select(. < $m.end)] | if length > 0 then $m.end - max else null end)}) ]
    | sort_by(.at) | map(.at |= r1 | .duration |= r1) as $steps
    | {wall: ($t1 - $t0 | r1), script: ($script_s | r1), agent: ($t1 - $t0 - $script_s | r1), steps: $steps,
       pipeline: {hunter_spread: (if ($h | length) > 0 then ($h | map(.end) | max - min) | r1 else null end),
                  verify_sum: (if ($v | length) > 0 and $vs != null then [$v[] | .end - $vs] | add | r1 else null end),
                  verify_wall: (if ($v | length) > 0 and $vs != null then ($v | map(.end) | max) - $vs | r1 else null end)}}
  ' "$run_dir/timing.jsonl" || die timing_failed "jq could not read timing.jsonl"
}

case "$cmd" in
  merge) merge "${3:-6}" ;;
  resolve) resolve ;;
  analyze) analyze ;;
  mark) mark "${3:-}" "${4:-}" ;;
  timing) timing ;;
  *) die bad_command "usage: findings.sh merge|resolve|analyze|mark|timing <run_dir>" ;;
esac
