#!/usr/bin/env bash
# Check bf dependencies against skills/setup/deps.json.
#
# Usage: setup.sh status
#        setup.sh check <name>...
#        setup.sh plan [core|all]
#        setup.sh install [core|all] [--only <name>]
#   status  read-only. Print every dependency and whether it is present.
#   check   print {"<name>": {"ready": bool, "path": "<launcher>"|null}} for the names given.
#           This is the one place that decides whether a tool is ready. The measured gate
#           runs the path it returns and never rebuilds the tool layout itself.
#   plan    print the install commands for the missing dependencies in scope (default all), in
#           deps.json order. A git tool builds its .venv with the placeholder <python 3.11+>,
#           because the interpreter may not exist until an earlier entry installs it. install
#           resolves the placeholder when it runs the command.
#   install run exactly the list plan prints, and continue past a failed entry. An entry whose
#           requires are not ready is skipped. --only <name> runs one entry, so the caller can
#           give each entry its own time limit. Without --only it prints {results, deps}.
#           Never runs curl|bash: with no brew on macOS it prints {"blocked":"no_brew",...}.
#
# deps.json fields: name, tier (core|optional), kind, features, requires (names that must be
# ready first, for the install order and for the install gate), and per kind: brew and apt (system, python_min), repo (git_tool).
# Kinds:
#   system      present when `command -v <name>` finds it
#   python_min  present when python3.13, 3.12, 3.11 or python3 reports version 3.11 or newer
#   git_tool    ready when ~/.bf/tools/<n>/<n> and ~/.bf/tools/<n>/.venv/bin/python are executable
#   likec4      the pinned build under the bf:visualize cache
#   typesafe    the key and the config flag, read from typesafe-setup.sh status
#
# Output: one JSON object on stdout. Errors: {"error":"<code>","detail":"..."} and exit 1.
# Test-only: BF_SETUP_PLATFORM=macos|linux|other forces the platform.
set -uo pipefail

die() { jq -cn --arg e "$1" --arg d "${2:-}" '{error:$e, detail:$d}' 2>/dev/null || printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }

command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=$(cd "$here/../../.." && pwd)
deps_file=$here/../deps.json
tools_dir=$HOME/.bf/tools

[ -f "$deps_file" ] || die registry_missing "$deps_file not found"

platform=other
case "${BF_SETUP_PLATFORM:-$(uname -s 2>/dev/null)}" in
  macos|Darwin) platform=macos ;;
  linux|Linux) platform=linux ;;
esac
pkg_manager=null
if [ "$platform" = macos ] && command -v brew >/dev/null 2>&1; then pkg_manager=brew; fi
if [ "$platform" = linux ] && command -v apt-get >/dev/null 2>&1; then pkg_manager=apt; fi

dep_names() { jq -r '.[].name' "$deps_file"; }
dep_field() { jq -r --arg n "$1" --arg k "$2" '.[] | select(.name == $n) | .[$k] // empty | if type == "array" then join(" ") else . end' "$deps_file"; }

# Sets PY_FOUND to the first interpreter at 3.11 or newer, and returns 1 when there is none.
# PY_SEEN holds the newest version found. Call it without a subshell so both survive.
PY_FOUND=""; PY_SEEN=""
find_python_modern() {
  local c p v
  PY_FOUND=""; PY_SEEN=""
  for c in python3.13 python3.12 python3.11 python3; do
    p=$(command -v "$c" 2>/dev/null) || continue
    v=$("$p" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null) || continue
    [ -n "$PY_SEEN" ] || PY_SEEN=$v
    if [ "$("$p" -c 'import sys; print(sys.version_info >= (3, 11))' 2>/dev/null)" = True ]; then
      PY_FOUND=$p; return 0
    fi
  done
  return 1
}

# Sets DETAIL and LAUNCHER for <name>. Returns 0 when the dependency is ready. It checks the
# dependency alone: the requires of an entry gate its install in run_entry.
DETAIL=""; LAUNCHER=""
probe() {
  local name=$1 kind p d bin v out
  kind=$(dep_field "$name" kind)
  DETAIL=""; LAUNCHER=""
  case "$kind" in
    system)
      p=$(command -v "$name" 2>/dev/null) || { DETAIL="not found on PATH"; return 1; }
      LAUNCHER=$p; DETAIL="found"; return 0 ;;
    python_min)
      if find_python_modern; then LAUNCHER=$PY_FOUND; DETAIL="found $PY_FOUND"; return 0; fi
      if [ -n "$PY_SEEN" ]; then DETAIL="newest is $PY_SEEN, need 3.11 or newer"; else DETAIL="no python3 found"; fi
      return 1 ;;
    git_tool)
      d=$tools_dir/$name
      [ -d "$d" ] || { DETAIL="not cloned"; return 1; }
      [ -x "$d/$name" ] || { DETAIL="launcher $d/$name missing"; return 1; }
      [ -x "$d/.venv/bin/python" ] || { DETAIL="no .venv"; return 1; }
      LAUNCHER=$d/$name; DETAIL="ready"; return 0 ;;
    likec4)
      v=$(bash "$plugin/skills/visualize/scripts/install-likec4.sh" --print-version 2>/dev/null) || { DETAIL="cannot read pinned version"; return 1; }
      bin=$(bash "$plugin/skills/visualize/scripts/install-likec4.sh" --print-bin 2>/dev/null)
      if [ -x "$bin" ]; then LAUNCHER=$bin; DETAIL="pinned $v installed"; return 0; fi
      DETAIL="pinned $v not installed"; return 1 ;;
    typesafe)
      out=$(bash "$plugin/skills/typesafe/scripts/typesafe-setup.sh" status 2>/dev/null) || { DETAIL="status failed, see /bf:typesafe"; return 1; }
      if [ "$(printf '%s' "$out" | jq -r '.enabled and .key_present' 2>/dev/null)" = true ]; then DETAIL="boosting on, key set"; return 0; fi
      if [ "$(printf '%s' "$out" | jq -r '.key_present' 2>/dev/null)" = true ]; then DETAIL="key set, boosting off. Run /bf:typesafe"; else DETAIL="no key. Run /bf:typesafe"; fi
      return 1 ;;
    *) DETAIL="unknown kind $kind"; return 1 ;;
  esac
}

status_deps() {
  local n
  for n in $(dep_names); do
    if probe "$n"; then ok=true; else ok=false; fi
    jq -cn --arg n "$n" --argjson ok "$ok" --arg d "$DETAIL" --arg p "$LAUNCHER" \
      --arg tier "$(dep_field "$n" tier)" --arg req "$(dep_field "$n" requires)" \
      --argjson f "$(jq -c --arg n "$n" '.[] | select(.name == $n) | .features' "$deps_file")" \
      '{name:$n, tier:$tier, present:$ok, detail:$d, path:(if $p == "" then null else $p end), requires:($req | split(" ") | map(select(. != ""))), features:$f}'
  done | jq -s '.'
}

cmd_status() {
  jq -cn --arg pl "$platform" --arg pm "$pkg_manager" --argjson deps "$(status_deps)" \
    '{platform:$pl, pkg_manager:(if $pm == "null" then null else $pm end), deps:$deps}'
}

cmd_check() {
  [ $# -gt 0 ] || die bad_args "check needs at least one dependency name"
  local n out='{}'
  for n in "$@"; do
    dep_names | grep -qxF -- "$n" || die unknown_dep "$n is not in deps.json"
    if probe "$n"; then ok=true; else ok=false; fi
    out=$(printf '%s' "$out" | jq -c --arg n "$n" --argjson ok "$ok" --arg p "$LAUNCHER" \
      '. + {($n): {ready:$ok, path:(if $p == "" then null else $p end)}}')
  done
  printf '%s\n' "$out"
}

PLACEHOLDER='<python 3.11+>'
TAB=$(printf '\t')
LIST=""; NEED_BREW=0

# A command another entry already lists runs once (node and npm share one brew formula).
add_cmd() {
  case "$LIST" in *"$TAB$2"$'\n'*) return ;; esac
  LIST="$LIST$1$TAB$2
"
}

# Fills LIST with "name<TAB>command" lines for the missing dependencies in scope, and NEED_BREW.
build_list() {
  local scope=$1 n kind d qd
  LIST=""; NEED_BREW=0
  for n in $(dep_names); do
    kind=$(dep_field "$n" kind)
    [ "$kind" = typesafe ] && continue
    [ "$scope" = core ] && [ "$(dep_field "$n" tier)" != core ] && continue
    probe "$n" && continue
    case "$kind" in
      system|python_min)
        case "$platform" in
          macos) add_cmd "$n" "brew install $(dep_field "$n" brew)"; NEED_BREW=1 ;;
          linux) add_cmd "$n" "sudo -n apt-get install -y $(dep_field "$n" apt)" ;;
          *) die unsupported_platform "bf:setup installs system tools with brew on macOS and apt on Linux" ;;
        esac ;;
      git_tool)
        d=$tools_dir/$n; qd=$(printf '%q' "$d")
        [ -d "$d" ] || add_cmd "$n" "git clone --depth 1 $(dep_field "$n" repo) $qd"
        add_cmd "$n" "$PLACEHOLDER -m venv $qd/.venv"
        add_cmd "$n" "$qd/.venv/bin/pip install -e $qd" ;;
      likec4)
        add_cmd "$n" "bash $(printf '%q' "$plugin")/skills/visualize/scripts/install-likec4.sh" ;;
    esac
  done
}

# Prints the blocked object and returns 0 when the list needs brew and brew is missing.
blocked_no_brew() {
  [ "$NEED_BREW" -eq 1 ] && [ "$pkg_manager" != brew ] || return 1
  jq -cn --arg h '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
    '{blocked:"no_brew", hint:$h}'
}

parse_scope() { # sets SCOPE and ONLY from the arguments
  SCOPE=all; ONLY=""
  while [ $# -gt 0 ]; do
    case "$1" in
      core|all) SCOPE=$1; shift ;;
      --only) [ -n "${2:-}" ] || die bad_args "--only needs a dependency name"; ONLY=$2; shift 2 ;;
      *) die bad_args "unknown argument: $1" ;;
    esac
  done
  [ -z "$ONLY" ] || dep_names | grep -qxF -- "$ONLY" || die unknown_dep "$ONLY is not in deps.json"
}

cmd_plan() {
  parse_scope "$@"
  build_list "$SCOPE"
  blocked_no_brew && return 0
  printf '%s' "$LIST" | jq -Rsc --arg scope "$SCOPE" --arg pl "$platform" --arg ph "$PLACEHOLDER" '
    (split("\n") | map(select(length > 0) | split("\t") | {name: .[0], cmd: .[1]})
      | reduce .[] as $c ([]; if length > 0 and .[-1].name == $c.name then .[-1].commands += [$c.cmd]
          else . + [{name: $c.name, commands: [$c.cmd]}] end)) as $steps
    | {scope:$scope, platform:$pl, steps:$steps}
      + (if ([$steps[].commands[] | select(contains($ph))] | length) > 0
         then {note: "\($ph) is replaced at run time by the Python 3.11 or newer interpreter found then."} else {} end)'
}

RES_OK=true; RES_DETAIL=""
# Runs the listed commands of one entry. Sets RES_OK and RES_DETAIL.
run_entry() {
  local n=$1 r cmd out py
  RES_OK=true; RES_DETAIL="installed"
  for r in $(dep_field "$n" requires); do
    if ! probe "$r"; then RES_OK=false; RES_DETAIL="skipped: requires $r, which is not ready ($DETAIL)"; return; fi
  done
  while IFS="$TAB" read -r name cmd; do
    [ "$name" = "$n" ] || continue
    case "$cmd" in
      "$PLACEHOLDER"*)
        find_python_modern || { RES_OK=false; RES_DETAIL="no Python 3.11 or newer found. Install python3-modern first"; return; }
        cmd="$(printf '%q' "$PY_FOUND")${cmd#"$PLACEHOLDER"}" ;;
    esac
    if ! out=$(bash -c "$cmd" 2>&1 </dev/null); then
      RES_OK=false
      case "$cmd" in
        "sudo -n "*) RES_DETAIL="sudo needs a password. Run this yourself: ! sudo ${cmd#sudo -n }" ;;
        *) RES_DETAIL="$cmd failed: $(printf '%s' "$out" | tail -n 1 | cut -c1-200)" ;;
      esac
      return
    fi
  done <<EOF2
$LIST
EOF2
  if ! probe "$n"; then RES_OK=false; RES_DETAIL="commands ran but the check still fails: $DETAIL"; fi
}

cmd_install() {
  parse_scope "$@"
  build_list "$SCOPE"
  blocked_no_brew && return 0
  local n results='[]'
  for n in $(printf '%s' "$LIST" | cut -f1 | awk '!seen[$0]++'); do
    [ -z "$ONLY" ] || [ "$n" = "$ONLY" ] || continue
    run_entry "$n"
    results=$(printf '%s' "$results" | jq -c --arg n "$n" --argjson ok "$RES_OK" --arg d "$RES_DETAIL" '. + [{name:$n, ok:$ok, detail:$d}]')
  done
  if [ -n "$ONLY" ]; then jq -cn --argjson r "$results" '{results:$r}'
  else jq -cn --argjson r "$results" --argjson d "$(cmd_status)" '{results:$r, deps:$d}'; fi
}

mode=${1:-}; [ $# -eq 0 ] || shift
case "$mode" in
  status) cmd_status ;;
  check) cmd_check "$@" ;;
  plan) cmd_plan "$@" ;;
  install) cmd_install "$@" ;;
  *) die bad_args "mode must be status, check, plan or install" ;;
esac
