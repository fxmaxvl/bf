#!/usr/bin/env bash
# Smoke test for setup.sh. Uses a fake HOME and a fake PATH, so it never touches the real ~/.bf
# and never installs anything. Run with both `bash` and macOS `/bin/bash`.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
setup=$here/setup.sh
deps=$here/../deps.json
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is required to run this smoke"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1${2:+: $2}"; }
expect() { # name, actual, expected
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi
}

HOME_DIR=$T/home
BIN=$T/bin
LOG=$T/calls.log

reset_env() {
  rm -rf "$HOME_DIR" "$BIN"; mkdir -p "$HOME_DIR" "$BIN"; : > "$LOG"
  local t p
  for t in jq bash uname dirname basename cat grep sed tr mktemp awk sort head ls find rm mkdir chmod cp ln date; do
    p=$(command -v "$t") && ln -s "$p" "$BIN/$t"
  done
}

# A stub prints nothing and logs its argv, unless a body is given.
stub() { # name [body]
  printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$LOG" "${2:-}" > "$BIN/$1"
  chmod +x "$BIN/$1"
}

# A fake python reports version $2 and builds a fake venv for `-m venv <dir>`.
mkpy() { # name version
  stub "$1" '
case "$1" in
  -m) if [ "$2" = venv ]; then mkdir -p "$3/bin"; printf "#!/bin/bash\n" > "$3/bin/python"; printf "#!/bin/bash\necho pip \"\$@\" >> '"$LOG"'\n" > "$3/bin/pip"; chmod +x "$3/bin/python" "$3/bin/pip"; fi ;;
  -c) case "$2" in
        *"(3, 11)"*) '"$(printf 'v=%s' "$2")"'; if [ "${v%%.*}" -gt 3 ] || [ "${v#*.}" -ge 11 ]; then echo True; else echo False; fi ;;
        *) echo '"$2"' ;;
      esac ;;
esac'
}

mktool() { # name: a ready git tool under the fake HOME
  local d=$HOME_DIR/.bf/tools/$1
  mkdir -p "$d/.venv/bin"
  printf '#!/bin/bash\n' > "$d/$1"; printf '#!/bin/bash\n' > "$d/.venv/bin/python"
  chmod +x "$d/$1" "$d/.venv/bin/python"
}

run() { env -i HOME="$HOME_DIR" PATH="$BIN" ${BF_SETUP_PLATFORM:+BF_SETUP_PLATFORM="$BF_SETUP_PLATFORM"} "${BASH:-bash}" "$setup" "$@"; }
field() { jq -r --arg n "$1" --arg k "$2" '.deps[] | select(.name == $n) | .[$k] | tostring' ; }

# --- registry shape ---
bad_req=$(jq -r '. as $all | to_entries[] | .key as $i | .value | .name as $n | .requires[]? as $r
  | select(([$all[:$i][] | .name] | index($r)) == null) | "\($n) needs \($r)"' "$deps")
expect "every requires entry names an earlier dependency" "$bad_req" ""
expect "every kind is a documented kind" \
  "$(jq -r '[.[] | .kind] | map(select(. != "system" and . != "python_min" and . != "git_tool" and . != "likec4" and . != "typesafe")) | join(",")' "$deps")" ""
expect "requires chain python3-modern, crapper, mutator" \
  "$(jq -r '[.[] | select(.name == "crapper" or .name == "dryer" or .name == "mutator" or .name == "likec4") | "\(.name):\(.requires | join(","))"] | join(" ")' "$deps")" \
  "likec4:node crapper:python3-modern dryer:python3-modern mutator:crapper"
expect "curl is a core dependency" "$(jq -r '.[] | select(.name == "curl") | .tier' "$deps")" "core"

# --- status and check ---
reset_env
out=$(run status)
expect "every dependency absent: only jq is present" \
  "$(printf '%s' "$out" | jq -r '[.deps[] | select(.present) | .name] | join(",")')" "jq"

reset_env; stub git
out=$(run status)
expect "git and jq present, others absent" \
  "$(printf '%s' "$out" | jq -r '[.deps[] | select(.present) | .name] | join(",")')" "git,jq"

reset_env; mkdir -p "$HOME_DIR/.bf/tools/crapper"; printf '#!/bin/bash\n' > "$HOME_DIR/.bf/tools/crapper/crapper"; chmod +x "$HOME_DIR/.bf/tools/crapper/crapper"
expect "crapper cloned with no .venv" "$(run status | field crapper detail)" "no .venv"

reset_env; mktool crapper
out=$(run status)
expect "crapper ready" "$(printf '%s' "$out" | field crapper present)" "true"
expect "ready crapper reports its launcher path" "$(printf '%s' "$out" | field crapper path)" "$HOME_DIR/.bf/tools/crapper/crapper"

reset_env; mktool mutator
expect "mutator ready but no ../crapper" "$(run status | field mutator detail)" "needs ../crapper"

reset_env; stub mutator
expect "a mutator on PATH does not make mutator present" "$(run status | field mutator present)" "false"

reset_env; mktool crapper
expect "check with two names" "$(run check crapper dryer)" \
  "$(jq -cn --arg p "$HOME_DIR/.bf/tools/crapper/crapper" '{crapper:{ready:true,path:$p}, dryer:{ready:false,path:null}}')"
expect "check rejects an unknown name" "$(run check nosuch | jq -r .error)" "unknown_dep"

reset_env; stub node; stub npm
expect "node needs npm too" "$(run status | field node present)" "true"
reset_env; stub node
expect "node without npm is absent" "$(run status | field node detail)" "node found, npm missing"

reset_env; mkpy python3 3.10
out=$(run status)
expect "python3-modern absent with only 3.10" "$(printf '%s' "$out" | field python3-modern present)" "false"
expect "python3-modern detail names the version seen" "$(printf '%s' "$out" | field python3-modern detail)" "newest is 3.10, need 3.11 or newer"
reset_env; mkpy python3 3.10; mkpy python3.12 3.12
expect "python3-modern found at python3.12" "$(run status | field python3-modern path)" "$BIN/python3.12"

reset_env
ver=$(bash "$here/../../visualize/scripts/install-likec4.sh" --print-version)
expect "likec4 absent without the cache" "$(run status | field likec4 present)" "false"
mkdir -p "$HOME_DIR/.bf/cache/likec4@$ver/node_modules/.bin"
printf '#!/bin/bash\n' > "$HOME_DIR/.bf/cache/likec4@$ver/node_modules/.bin/likec4"; chmod +x "$HOME_DIR/.bf/cache/likec4@$ver/node_modules/.bin/likec4"
expect "likec4 present with the pinned cache" "$(run status | field likec4 present)" "true"

reset_env
expect "typesafe without a key points to /bf:typesafe" "$(run status | field typesafe detail)" "no key. Run /bf:typesafe"

reset_env; stub git; mktool crapper
before=$(cd "$HOME_DIR" && find . | sort)
run status >/dev/null; run check crapper >/dev/null
expect "status and check write nothing under HOME" "$(cd "$HOME_DIR" && find . | sort)" "$before"

echo "---- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
