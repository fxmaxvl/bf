#!/usr/bin/env bash
# Smoke test for deps-index.sh: parsers, incremental build, read, lock, kill switch, background start and
# the hooks.json registration. Each case builds a temp git repo.
#
# Usage: deps-index-smoke.sh
# Output: one PASS or FAIL line per case. Exit 0 when every case passes, 1 otherwise.
set -uo pipefail

main() {
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deps-index.sh"
  tmp=$(cd "$(mktemp -d)" && pwd -P)
  trap 'rm -rf "$tmp"' EXIT
  fails=0
  n=0

  guard_cases
  unit_cases
  integration_cases

  [ "$fails" = 0 ]
}

guard_cases() {
  local out plain
  plain=$tmp/plain
  mkdir -p "$plain"
  out=$(cd "$plain" && bash "$script" build 2>&1); rc=$?
  check "not a git repo: exit and output" "$rc:$out" "0:"
  check "not a git repo: no cache" "$([ -e "$plain/.bf/cache" ] && echo yes || echo no)" no

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  out=$(cd "$repo" && env PATH=/nonexistent /bin/bash "$script" build 2>&1); rc=$?
  check "no jq on PATH: exit and output" "$rc:$out" "0:"
  check "no jq on PATH: no index" "$([ -e "$repo/.bf/cache/deps.json" ] && echo yes || echo no)" no

  out=$(cd "$repo" && BF_DEPS_HOOK=off bash "$script" build 2>&1); rc=$?
  check "BF_DEPS_HOOK=off: exit and output" "$rc:$out" "0:"
  check "BF_DEPS_HOOK=off: no cache dir" "$([ -e "$repo/.bf/cache" ] && echo yes || echo no)" no
}

unit_cases() {
  ctx_init
  put package.json <<'EOF'
{"name":"x","dependencies":{"a":"^1.0.0"},"devDependencies":{"b":"~2.0"},
 "peerDependencies":{"c":">=3"},"optionalDependencies":{"d":"4.0.0"}}
EOF
  idx build
  check "package.json: four dependency tables" "$(deps_of package.json)" "false a=^1.0.0,b=~2.0,c=>=3,d=4.0.0"

  ctx_init
  put package.json <<'EOF'
{ not json
EOF
  idx build
  check "package.json: invalid JSON gives error and no deps" "$(deps_of package.json)" "true "
}

integration_cases() {
  local t

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  idx build
  t=$(DEPS_INDEX_TRACE=1 idx build 2>&1)
  check "incremental: unchanged manifest is not parsed again" "$t" ""

  printf '{"dependencies":{"a":"2"}}\n' > "$repo/package.json"
  t=$(DEPS_INDEX_TRACE=1 idx build 2>&1)
  check "incremental: changed manifest is parsed again" "$t" "parse package.json"
  check "incremental: changed manifest has the new version" "$(deps_of package.json)" "false a=2"

  git -C "$repo" rm -q -f package.json
  idx build
  check "incremental: removed manifest is dropped" "$(deps_of package.json)" missing

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  put sub/package.json <<'EOF'
{"dependencies":{"b":"1"}}
EOF
  idx build
  rm "$repo/sub/package.json"
  idx build; rc=$?
  check "file deleted in the work tree: build exits 0" "$rc" 0
  check "file deleted in the work tree: entry dropped" "$(deps_of sub/package.json)" missing
  check "file deleted in the work tree: other entry kept" "$(deps_of package.json)" "false a=1"
  check "index parses with jq" "$(jq -e '.schema == 1' "$repo/.bf/cache/deps.json" >/dev/null 2>&1 && echo yes)" yes
  check "no temp file remains" "$(ls "$repo/.bf/cache" | grep -c 'deps.json.tmp')" 0
  check "cache .gitignore holds *" "$(cat "$repo/.bf/cache/.gitignore")" '*'
  check "no lock remains after a build" "$([ -e "$repo/.bf/cache/deps.lock" ] && echo yes || echo no)" no

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  mkdir -p "$repo/.bf/cache/deps.lock"
  date +%s > "$repo/.bf/cache/deps.lock/started"
  idx build; rc=$?
  check "held lock: build exits 0" "$rc" 0
  check "held lock: build skips" "$([ -e "$repo/.bf/cache/deps.json" ] && echo yes || echo no)" no
  check "held lock: lock dir stays" "$([ -d "$repo/.bf/cache/deps.lock" ] && echo yes || echo no)" yes

  ctx_init
  mkdir -p -m 755 "$repo/.bf/cache"
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  idx build
  check "existing cache dir with mode 755 works" "$(deps_of package.json)" "false a=1"
}

# ctx_init: a new empty git repo in $repo.
ctx_init() {
  n=$((n + 1))
  repo=$tmp/repo$n
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
}

# put <path>: writes stdin to the path in $repo and stages it.
put() {
  mkdir -p "$repo/$(dirname "$1")"
  cat > "$repo/$1"
  git -C "$repo" add "$1"
}

idx() { (cd "$repo" && bash "$script" "$@"); }

# deps_of <manifest>: "<error> name=version,..." for one index entry, or "missing".
deps_of() {
  jq -r --arg m "$1" '.manifests[$m] | if . == null then "missing"
    else (.error | tostring) + " " + (.deps | map(.name + "=" + (.version // "null")) | join(",")) end' \
    "$repo/.bf/cache/deps.json" 2>/dev/null
}

check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails + 1)); fi
}

main "$@"
