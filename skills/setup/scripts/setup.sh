#!/usr/bin/env bash
# Check bf dependencies against skills/setup/deps.json.
#
# Usage: setup.sh status
#        setup.sh check <name>...
#   status  read-only. Print every dependency and whether it is present.
#   check   print {"<name>": {"ready": bool, "path": "<launcher>"|null}} for the names given.
#           This is the one place that decides whether a tool is ready. The measured gate
#           runs the path it returns and never rebuilds the tool layout itself.
#
# deps.json fields: name, tier (core|optional), kind, features, requires (names that must be
# present first), and per kind: brew and apt (system, python_min), repo (git_tool).
# Kinds:
#   system      present when `command -v <name>` finds it (node also needs npm)
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
plugin=$here/../../..
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

# Sets DETAIL and LAUNCHER for <name>. Returns 0 when the dependency is ready.
DETAIL=""; LAUNCHER=""
probe() {
  local name=$1 kind p d bin v out
  kind=$(dep_field "$name" kind)
  DETAIL=""; LAUNCHER=""
  case "$kind" in
    system)
      p=$(command -v "$name" 2>/dev/null) || { DETAIL="not found on PATH"; return 1; }
      if [ "$name" = node ] && ! command -v npm >/dev/null 2>&1; then DETAIL="node found, npm missing"; return 1; fi
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
      if [ "$name" = mutator ] && [ ! -d "$tools_dir/crapper" ]; then DETAIL="needs ../crapper"; return 1; fi
      LAUNCHER=$d/$name; DETAIL="ready"; return 0 ;;
    likec4)
      v=$(bash "$plugin/skills/visualize/scripts/install-likec4.sh" --print-version 2>/dev/null) || { DETAIL="cannot read pinned version"; return 1; }
      bin=${BF_LIKEC4_CACHE_DIR:-$HOME/.bf/cache}/likec4@$v/node_modules/.bin/likec4
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

mode=${1:-}; [ $# -eq 0 ] || shift
case "$mode" in
  status) cmd_status ;;
  check) cmd_check "$@" ;;
  *) die bad_args "mode must be status or check" ;;
esac
