#!/usr/bin/env bash
# The only script SKILL.md calls: one build attempt, or the once-per-run init.
#
# Usage:  build.sh --init --doc <path>   resolve paths, reset run state; run once, before writing the model
#         build.sh --doc <path>          one attempt: pre-checks -> install -> stage -> validate -> build -> classify
# Output: --init prints the viz-paths.sh JSON.
#         An attempt prints {ok, attempt, final, source, retryable, model_stamped, errors[], warnings[], html,
#         model_path, views[], element_count, tbd_count, sensitive_reminder}. errors[] is [{file,message,lines[]}];
#         source is model|spec|staging|toolchain|null; retryable is true only for model faults.
# Errors: {"error":...,"detail":...} + exit 1 — usage, not_initialized, jq_missing, plus any viz-paths.sh error.
#
# Side effects it owns: <build_dir>/.run-state.json ({attempts, model_existed}; deleted on any final outcome);
# the attempt cap (3 attempts in total); on a final failure of a model fault it stamps a FAILED VALIDATION first
# line into <slug>.c4 (success strips it); on any final failure it deletes index.html and mapping.md.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MAX_ATTEMPTS=3
STAGED_BASE="base-spec.c4"; STAGED_OVERRIDE="override.c4"; STAGED_MODEL="model.c4"
MARKER='// bf:visualize: FAILED VALIDATION — see diagnostics from the last run; fix and re-run /bf:visualize'

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
fail() { jq -cn --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'; exit 1; }

init=false; doc=
while [ $# -gt 0 ]; do
  case "$1" in
    --init) init=true; shift ;;
    --doc) [ $# -ge 2 ] || fail usage "--doc needs a path"; doc=$2; shift 2 ;;
    *) fail usage "unknown argument: $1 (usage: build.sh [--init] --doc <path>)" ;;
  esac
done
[ -n "$doc" ] || fail usage "build.sh [--init] --doc <path>"

if ! paths=$(bash "$here/viz-paths.sh" "$doc"); then printf '%s\n' "$paths"; exit 1; fi
pj() { jq -r ".$1" <<<"$paths"; }
kind=$(pj kind); project_root=$(pj project_root); model_path=$(pj model_path)
build_dir=$(pj build_dir); html_path=$(pj html_path); mapping_path=$(pj mapping_path)
state=$build_dir/.run-state.json

if [ "$init" = true ]; then
  mkdir -p "$build_dir"
  rm -f "$html_path" "$mapping_path"
  jq -cn --argjson e "$(pj model_exists)" '{attempts:0, model_existed:$e}' > "$state"
  printf '%s\n' "$paths"
  exit 0
fi

[ -f "$state" ] || fail not_initialized "no run state at $state — start with: build.sh --init --doc $doc"
attempt=$(( $(jq -r .attempts "$state") + 1 ))
model_existed=$(jq -r .model_existed "$state")
jq --argjson a "$attempt" '.attempts = $a' "$state" > "$state.tmp" && mv "$state.tmp" "$state"

ok=false; source_=; retryable=false; errors='[]'; warnings='[]'; html=null

add_error() { errors=$(jq -c --arg f "$1" --arg m "$2" --argjson l "${3:-[]}" '. + [{file:$f, message:$m, lines:$l}]' <<<"$errors"); }
set_fault() { source_=$1; retryable=$2; }

install_json=; ws=$build_dir/workspace; out_dir=$build_dir/out

run_checks() {
  [ -f "$model_path" ] || { set_fault staging false; add_error "$model_path" "model file not found — write it before running build.sh --doc"; return; }
  local mf; mf=$(bash "$here/c4-facts.sh" "$model_path")
  if [ "$(jq -r .has_specification <<<"$mf")" = true ]; then
    set_fault model true
    add_error "$model_path" "remove the specification block: element kinds come from the bf:visualize base spec and the optional override, never from the model"
    return
  fi

  local spec; spec=$(bash "$here/resolve-spec.sh" "$project_root")
  base=$(jq -r .base <<<"$spec"); override=$(jq -r '.override // ""' <<<"$spec")
  if [ -n "$override" ]; then
    local dup
    dup=$(jq -rn --argjson b "$(bash "$here/c4-facts.sh" "$base")" --argjson o "$(bash "$here/c4-facts.sh" "$override")" \
      '[$o.kinds[] | select(. as $k | $b.kinds | index($k))] | first // empty')
    if [ -n "$dup" ]; then
      set_fault spec false
      add_error "$override" "fix your override at $override: redefines base kind $dup"
      return
    fi
  fi

  if ! install_json=$(bash "$here/install-likec4.sh"); then
    set_fault toolchain false
    add_error "" "$(jq -r '"\(.error): \(.detail)"' <<<"$install_json")"
    return
  fi
  local bin; bin=$(jq -r .bin <<<"$install_json")
  jq -c .allowlist <<<"$install_json" > "$build_dir/workspace-allow.json"

  rm -rf "$ws" "$out_dir"; mkdir -p "$ws"
  cp "$base" "$ws/$STAGED_BASE"
  [ -z "$override" ] || cp "$override" "$ws/$STAGED_OVERRIDE"
  cp "$model_path" "$ws/$STAGED_MODEL"

  local log rc
  log=$build_dir/likec4.log
  set +e; "$bin" validate "$ws" > "$log" 2>&1; rc=$?; set -e
  if ! diagnose "$log" "$rc" "$base" "$override"; then return; fi
  set +e; "$bin" build --output-single-file --use-hash-history -o "$out_dir" "$ws" > "$log" 2>&1; rc=$?; set -e
  if ! diagnose "$log" "$rc" "$base" "$override"; then return; fi
  [ -f "$out_dir/index.html" ] || { set_fault staging false; add_error "$out_dir/index.html" "likec4 build finished without producing index.html"; return; }
  mv "$out_dir/index.html" "$html_path"
  ok=true; html=$(jq -cn --arg h "$html_path" '$h')
}

# Args: <log> <rc> <base spec path> <override path or empty>.
# Returns 0 when the likec4 run was clean; otherwise records the fault and returns 1.
diagnose() {
  local base=$3 override=$4 c
  c=$(bash "$here/classify-output.sh" "$1" --allowlist "$build_dir/workspace-allow.json")
  warnings=$(jq -c .warnings <<<"$c")
  local has_warn has_err
  has_warn=$(jq '.warnings | length > 0' <<<"$c"); has_err=$(jq '.errors | length > 0' <<<"$c")
  [ "$2" -ne 0 ] || [ "$has_warn" = true ] || [ "$has_err" = true ] || return 0

  local spec_hit=false model_hit=false i n file lines
  n=$(jq '.errors | length' <<<"$c")
  for ((i = 0; i < n; i++)); do
    file=$(jq -r ".errors[$i].file" <<<"$c"); lines=$(jq -c ".errors[$i].lines" <<<"$c")
    case "$(basename "$file")" in
      "$STAGED_MODEL") model_hit=true; add_error "$model_path" "likec4 reported errors in $model_path" "$lines" ;;
      "$STAGED_OVERRIDE") spec_hit=true; add_error "$override" "fix your override at $override" "$lines" ;;
      "$STAGED_BASE") spec_hit=true; add_error "$base" "bf:visualize base spec is invalid — plugin bug, please report ($base)" "$lines" ;;
      *) add_error "" "likec4 reported an error it could not attribute to a file" "$lines" ;;
    esac
  done

  if [ "$spec_hit" = true ]; then set_fault spec false
  elif [ "$has_warn" = true ] || [ "$model_hit" = true ]; then set_fault model true
  else set_fault staging false; add_error "" "likec4 exited with status $2 and no attributable diagnostic" "[]"
  fi
  return 1
}

run_checks

final=false
{ [ "$ok" = true ] || [ "$attempt" -ge "$MAX_ATTEMPTS" ] || [ "$retryable" = false ]; } && final=true

model_stamped=false; sensitive=false
if [ "$final" = true ]; then
  if [ "$ok" = true ]; then
    if [ -f "$model_path" ] && [ "$(head -n 1 "$model_path")" = "$MARKER" ]; then
      tail -n +2 "$model_path" > "$model_path.tmp" && mv "$model_path.tmp" "$model_path"
    fi
  else
    rm -f "$html_path" "$mapping_path"
    if [ "$source_" = model ]; then
      if [ "$(head -n 1 "$model_path")" != "$MARKER" ]; then
        { printf '%s\n' "$MARKER"; cat "$model_path"; } > "$model_path.tmp" && mv "$model_path.tmp" "$model_path"
      fi
      model_stamped=true
    fi
  fi
  if [ "$kind" = arch-audit ] && [ "$model_existed" = false ] && [ -f "$model_path" ]; then sensitive=true; fi
  rm -f "$state"
fi
rm -rf "$out_dir"

facts='{"views":[],"element_count":0,"tbd_count":0}'
[ ! -f "$model_path" ] || facts=$(bash "$here/c4-facts.sh" "$model_path")

jq -cn --argjson ok "$ok" --argjson attempt "$attempt" --argjson final "$final" --arg source "$source_" \
  --argjson retryable "$retryable" --argjson stamped "$model_stamped" --argjson errors "$errors" \
  --argjson warnings "$warnings" --argjson html "$html" --arg model "$model_path" --argjson facts "$facts" \
  --argjson sensitive "$sensitive" \
  '{ok:$ok, attempt:$attempt, final:$final, source:(if $source == "" then null else $source end), retryable:$retryable, model_stamped:$stamped,
    errors:$errors, warnings:$warnings, html:$html, model_path:$model, views:$facts.views,
    element_count:$facts.element_count, tbd_count:$facts.tbd_count, sensitive_reminder:$sensitive}'
