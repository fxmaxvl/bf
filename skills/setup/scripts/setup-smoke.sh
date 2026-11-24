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
  for t in jq bash uname dirname basename cat grep sed tr mktemp awk sort head tail cut ls find rm mkdir chmod cp ln date; do
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


# --- plan and install: stubs stand in for the package managers, git and pip ---
AVAIL=$T/avail
BREW_FAIL=$T/brew_fail; SUDO_FAIL=$T/sudo_fail; GIT_FAIL=$T/git_fail

# What a package manager "installs": a stub from $AVAIL when one exists, else an empty executable.
PKG_BODY='
for a in "$@"; do
  case "$a" in install|-y|-n|apt-get) continue ;; esac
  if [ -f "'$BREW_FAIL'" ] && grep -qxF "$a" "'$BREW_FAIL'"; then echo "no formula $a" >&2; exit 1; fi
  n=$a; case "$a" in python@3.12|python3.12-venv|python3.12) n=python3.12 ;; nodejs) n=node ;; esac
  if [ -x "'$AVAIL'/$n" ]; then cp "'$AVAIL'/$n" "'$BIN'/$n"; else printf "#!/bin/bash\n" > "'$BIN'/$n"; chmod +x "'$BIN'/$n"; fi
done'

stubs_for_install() {
  mkdir -p "$AVAIL"
  local keep=$BIN; BIN=$AVAIL; mkpy python3.12 3.12; BIN=$keep
  printf '#!/bin/bash\necho "0.0.0"\n' > "$AVAIL/likec4"
  stub brew "$PKG_BODY"
  stub apt-get "$PKG_BODY"
  stub sudo '[ -f "'$SUDO_FAIL'" ] && exit 1; shift; exec "$@"'
  stub git '
if [ "$1" = clone ]; then
  for a; do dest=$a; done
  if [ -f "'$GIT_FAIL'" ] && grep -qxF "$(basename "$dest")" "'$GIT_FAIL'"; then echo "fatal: unable to access" >&2; exit 128; fi
  mkdir -p "$dest"; printf "#!/bin/bash\n" > "$dest/$(basename "$dest")"; chmod +x "$dest/$(basename "$dest")"
fi'
  stub npm 'for a; do case "$a" in --prefix) take=1; continue ;; esac; [ "${take:-0}" = 1 ] && { prefix=$a; take=0; }; done
mkdir -p "$prefix/node_modules/.bin"; printf "#!/bin/bash\necho %s\n" "'"$ver"'" > "$prefix/node_modules/.bin/likec4"; chmod +x "$prefix/node_modules/.bin/likec4"'
  rm -f "$BREW_FAIL" "$SUDO_FAIL" "$GIT_FAIL"
}

has_no_calls() { [ -z "$(grep -v ' -c ' "$LOG")" ]; }
names() { jq -r '[.steps[].name] | join(",")'; }

ver=$(bash "$here/../../visualize/scripts/install-likec4.sh" --print-version)
export BF_SETUP_PLATFORM=macos

reset_env; stubs_for_install
expect "plan core lists only the missing core dependencies" "$(run plan core | names)" "gh,python3,curl"
expect "plan never lists typesafe" "$(run plan | names | tr ',' '\n' | grep -c '^typesafe$')" "0"
expect "plan prints the python placeholder and a note for git tools" \
  "$(run plan | jq -r '[(.steps[] | select(.name == "crapper") | .commands[1] | startswith("<python 3.11+> -m venv")), (.note | contains("<python 3.11+>"))] | join(",")')" "true,true"
expect "plan lists requirements before dependents" \
  "$(run plan | names)" "gh,python3,curl,node,likec4,python3-modern,crapper,dryer,mutator"

reset_env; stubs_for_install; rm -f "$BIN/brew"
out=$(run plan)
expect "plan on macOS without brew is blocked" "$(printf '%s' "$out" | jq -r .blocked)" "no_brew"
expect "the no_brew hint is printed, not run" "$(printf '%s' "$out" | jq -r '.hint | startswith("/bin/bash -c")')" "true"
out=$(run install)
expect "install on macOS without brew is blocked" "$(printf '%s' "$out" | jq -r .blocked)" "no_brew"
has_no_calls && ok "a blocked install runs nothing" || bad "a blocked install runs nothing" "$(cat "$LOG")"

# A batch where python3-modern and crapper are both missing at plan time.
reset_env; stubs_for_install
plan_json=$(run plan)
: > "$LOG"
out=$(run install)
expect_cmds=$(printf '%s' "$plan_json" | jq -r '.steps[] | select(.name != "likec4") | .commands[]' \
  | sed -e 's|^<python 3.11+>|python3.12|' -e 's|^[^ ]*/\.venv/bin/pip|pip|')
actual_cmds=$(grep -v -e ' -c ' -e '^npm ' "$LOG")
expect "install runs the same commands plan printed" "$actual_cmds" "$expect_cmds"
expect "install of the batch reports no failure" "$(printf '%s' "$out" | jq -r '[.results[] | select(.ok | not) | .name] | join(",")')" ""
expect "python3-modern and crapper install in one batch" \
  "$(printf '%s' "$out" | jq -r '[.results[] | select(.name == "python3-modern" or .name == "crapper") | .ok] | join(",")')" "true,true"
expect "the placeholder resolves to the interpreter installed in the batch" \
  "$(grep -c "^python3.12 -m venv $HOME_DIR/.bf/tools/crapper/.venv" "$LOG")" "1"
expect "crapper installs before mutator" \
  "$(grep -n -e 'git clone .*crapper' -e 'git clone .*mutator' "$LOG" | sed 's/.*unclebob\/\([a-z]*\).git.*/\1/' | tr '\n' ',')" "crapper,mutator,"
expect "likec4 installs after node in the batch" "$(printf '%s' "$out" | jq -r '[.results[] | select(.name == "likec4") | .ok] | join(",")')" "true"
expect "install prints the status of every dependency" "$(printf '%s' "$out" | jq -r '[.deps.deps[] | select(.present | not) | .name] | join(",")')" "typesafe"
: > "$LOG"
out=$(run install)
has_no_calls && ok "a second install logs no command" || bad "a second install logs no command" "$(cat "$LOG")"
expect "a second install reports no result" "$(printf '%s' "$out" | jq -c .results)" "[]"

reset_env; stubs_for_install; mkpy python3.12 3.12; stub gh; stub python3; stub curl; stub node; stub npm; mktool crapper
: > "$LOG"
out=$(run install --only dryer)
expect "install --only runs only that entry" "$(printf '%s' "$out" | jq -c '[.results[].name]')" '["dryer"]'
expect "install --only dryer touches no other tool" "$(grep -c -e 'crapper' -e 'mutator' "$LOG")" "0"

reset_env; stubs_for_install
: > "$LOG"
out=$(run install --only crapper)
expect "install --only skips an entry whose requirement is missing" \
  "$(printf '%s' "$out" | jq -r '.results[0] | "\(.ok) \(.detail | startswith("skipped: requires python3-modern"))"')" "false true"
has_no_calls && ok "a skipped entry runs no command" || bad "a skipped entry runs no command" "$(cat "$LOG")"

reset_env; stubs_for_install
echo "python@3.12" > "$BREW_FAIL"
out=$(run install)
expect "no python 3.11 skips every tool that requires it" \
  "$(printf '%s' "$out" | jq -r '[.results[] | select(.ok | not) | .name] | join(",")')" "python3-modern,crapper,dryer,mutator"
expect "the skip detail names python3-modern" \
  "$(printf '%s' "$out" | jq -r '[.results[] | select(.name == "dryer") | .detail | startswith("skipped: requires python3-modern")] | join(",")')" "true"
expect "a failed entry does not stop an unrelated one" \
  "$(printf '%s' "$out" | jq -r '[.results[] | select(.name == "likec4") | .ok] | join(",")')" "true"

reset_env; stubs_for_install
echo "gh" > "$BREW_FAIL"
out=$(run install)
expect "a failing brew for one dependency does not stop the next" \
  "$(printf '%s' "$out" | jq -r '[.results[] | select(.name == "gh" or .name == "python3") | .ok] | join(",")')" "false,true"

reset_env; stubs_for_install
echo "crapper" > "$GIT_FAIL"
out=$(run install)
expect "a failed clone of crapper skips mutator" \
  "$(printf '%s' "$out" | jq -r '[.results[] | select(.name == "crapper" or .name == "mutator") | "\(.name):\(.ok)"] | join(",")')" "crapper:false,mutator:false"
expect "the mutator skip names crapper" \
  "$(printf '%s' "$out" | jq -r '.results[] | select(.name == "mutator") | .detail | startswith("skipped: requires crapper")')" "true"
expect "dryer still installs after a crapper failure" \
  "$(printf '%s' "$out" | jq -r '.results[] | select(.name == "dryer") | .ok')" "true"

reset_env; stubs_for_install; stub gh; stub python3; stub curl; stub node; stub npm; mkpy python3.12 3.12
stub likec4
mkdir -p "$HOME_DIR/.bf/cache/likec4@$ver/node_modules/.bin"; cp "$BIN/likec4" "$HOME_DIR/.bf/cache/likec4@$ver/node_modules/.bin/likec4"
rm -f "$BIN/brew"
expect "only git tools missing on macOS without brew is not blocked" "$(run plan | names)" "crapper,dryer,mutator"

reset_env; stubs_for_install
export BF_SETUP_PLATFORM=linux
plan_json=$(run plan core)
expect "the Linux plan uses sudo -n apt-get" "$(printf '%s' "$plan_json" | jq -r '.steps[0].commands[0]')" "sudo -n apt-get install -y gh"
touch "$SUDO_FAIL"
out=$(run install core)
expect "a failing sudo gives the ! sudo line" \
  "$(printf '%s' "$out" | jq -r '.results[] | select(.name == "gh") | .detail')" "sudo needs a password. Run this yourself: ! sudo apt-get install -y gh"
rm -f "$SUDO_FAIL"; : > "$LOG"
out=$(run install core)
expect "the Linux install runs through sudo -n" "$(grep -c '^sudo -n apt-get install -y' "$LOG")" "3"
export BF_SETUP_PLATFORM=other
reset_env
expect "an unsupported platform is an error" "$(run plan core | jq -r .error)" "unsupported_platform"

echo "---- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
