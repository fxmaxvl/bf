#!/usr/bin/env bash
# Dependency index of a git repo: the declared dependencies of every tracked manifest, kept in
# .bf/cache/deps.json. The SessionStart hook starts the build in the background. Skills run read, which
# also builds and writes .bf/cache/, so an entry is never older than its manifest.
#
# Usage: deps-index.sh build [--background]   bring the index up to date. --background reads the hook
#                                             input JSON on stdin, takes cwd from it and returns at once.
#        deps-index.sh read [path ...]        build, then print a JSON array of {name, version, manifest}.
#                                             With paths, print only the manifests at the repo root and
#                                             under those paths. A relative path starts at the cwd. "." at
#                                             the repo root, or the root path, prints only the root manifests.
#        deps-index.sh names                  print the manifest file names the index covers.
# Env:   BF_DEPS_HOOK=off turns build and read off. names still prints. DEPS_INDEX_TRACE=1 prints
#        "parse <path>" on stderr for each manifest that is parsed. DEPS_INDEX_TEST_DELAY=<seconds> makes
#        build wait before it writes.
# Output: build prints nothing. read prints nothing when it fails, when jq is missing, when the directory is
#         not a git repo, when a live build holds the lock for more than 5 seconds, or when every path is
#         outside the repo.
# Limits: only tracked manifests count, so a new manifest is invisible until it is staged. BUILD files keep
#         external labels only (@repo//...). The awk parsers read the common table shapes and are best
#         effort. A manifest that fails to parse gets error true and no dependencies.
#         The hook indexes only the repo of the session cwd. A different worktree has its own toplevel and its
#         own .bf/cache, so the first read there does a full cold build in the foreground.
set -uo pipefail
# Globbing stays off. The unquoted $MANIFEST_NAMES holds requirements*.txt, and a glob would expand it
# against the cwd. Only sweep_dead_work_dirs turns it on.
set -f
# _here is absolute, so start_background can name this script after it changes directory. It uses the builtins
# cd and pwd, not dirname, because the no-jq smoke case runs with an empty PATH. A hook that cannot find its
# guard ends quietly.
_dir=${BASH_SOURCE[0]%/*}
[ "$_dir" != "${BASH_SOURCE[0]}" ] || _dir=.
_here=$(cd "$_dir" 2>/dev/null && pwd) || exit 0
source "$_here/dir-guard.sh" 2>/dev/null || exit 0

MANIFEST_NAMES="package.json BUILD.bazel BUILD MODULE.bazel pom.xml build.gradle build.gradle.kts pyproject.toml requirements*.txt go.mod Cargo.toml"

root=
cache=
lock=
touched=0

is_manifest() {
  local pat
  for pat in $MANIFEST_NAMES; do
    case $1 in $pat) return 0 ;; esac
  done
  return 1
}

# The guard is shared with the prose hooks (dir-guard.sh). It skips the mode 700 check, which only the prose
# record dir needs.
open_repo() {
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  cache=$root/.bf/cache
  lock=$cache/deps.lock
  [ ! -L "$root/.bf" ] && [ ! -L "$cache" ] || return 1
  mkdir -p "$cache" 2>/dev/null && dir_guard_check "$cache" "$(id -u)" || return 1
  [ -e "$cache/.gitignore" ] || printf '*\n' > "$cache/.gitignore"
}

# lock_acquire <wait_seconds>: mkdir is atomic and flock(1) is missing on macOS. The lock holds the owner PID
# and a start time. A lock older than 60 seconds belongs to a killed build, and a live build refreshes the
# time (lock_touch). The EXIT trap is set only after mkdir succeeds, and it removes the lock only while the
# lock still names this process, or a build that lost its lock would delete the lock of the next holder.
# The work files live outside the lock dir (deps.work.<pid>), so a steal cannot delete them.
lock_acquire() {
  local wait=$1 waited=0 started now
  while :; do
    if mkdir "$lock" 2>/dev/null; then
      date +%s > "$lock/started"
      printf '%s\n' "$$" > "$lock/owner"
      trap lock_release EXIT
      return 0
    fi
    now=$(date +%s)
    started=$(cat "$lock/started" 2>/dev/null)
    # The owner makes the dir first and writes started after, so a missing started is normally that short gap.
    # Starting the clock here makes a lock whose owner died in the gap expire too, in place of staying forever.
    if [ -z "$started" ]; then
      [ -d "$lock" ] && printf '%s\n' "$now" > "$lock/started" 2>/dev/null
      started=$now
    fi
    if [ $((now - started)) -gt 60 ]; then
      lock_steal "$started"
      continue
    fi
    [ "$waited" -ge "$wait" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
}

# lock_steal <stale_started>: removes a stale lock. A check and an rm -rf are two steps, so a second caller could
# delete the fresh lock of the first stealer. The mv is atomic, so only one caller gets the stale dir. That
# caller deletes it only when it still holds the stale start time. A caller whose mv fails goes back to the loop.
lock_steal() {
  local stale=$cache/deps.lock.stale.$$
  rm -rf "$stale"
  [ "$(cat "$lock/started" 2>/dev/null)" = "$1" ] || return 0
  mv "$lock" "$stale" 2>/dev/null || return 0
  if [ "$(cat "$stale/started" 2>/dev/null)" != "$1" ] && [ ! -e "$lock" ]; then
    mv "$stale" "$lock" 2>/dev/null
  fi
  rm -rf "$stale"
}

# sweep_dead_work_dirs: removes the deps.work.<pid> dirs of killed builds. The caller holds the lock. The glob
# needs globbing, so it is turned on for the loop only.
sweep_dead_work_dirs() {
  local d
  set +f
  for d in "$cache"/deps.work.*; do
    [ -d "$d" ] && ! kill -0 "${d##*.}" 2>/dev/null && rm -rf "$d"
  done
  set -f
}

lock_release() {
  [ "$(cat "$lock/owner" 2>/dev/null)" = "$$" ] && rm -rf "$lock"
  rm -rf "$cache/deps.work.$$"
  rm -f "$cache/deps.json.tmp.$$"
}

# lock_touch: refreshes the start time at most every 10 seconds. A build on a large repo passes 60 seconds,
# and without it a second caller would steal the lock of a live build.
lock_touch() {
  [ $((SECONDS - touched)) -ge 10 ] || return 0
  touched=$SECONDS
  date +%s > "$lock/started" 2>/dev/null
  return 0
}

parse_package_json() {
  jq -r '[.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
         | map(select(type == "object")) | .[] | to_entries[] | "\(.key)\t\(.value | tostring)"' "$1"
}

# The awk parsers print "name<TAB>version" lines and leave the version empty when it is unknown. BSD awk
# on macOS has no gensub and no IGNORECASE, so they use POSIX awk only.
read -r -d '' AWK_LIB <<'EOF'
# req(s): a PEP 508 style requirement such as "uvicorn[standard]==0.30; python_version>'3'".
function req(s,   name, rest) {
  sub(/;.*/, "", s); sub(/\\$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s)
  if (s == "" || s ~ /^[A-Za-z]+(\+[A-Za-z]+)?:\/\//) return
  if (!match(s, /^[A-Za-z0-9][A-Za-z0-9._-]*/)) return
  name = substr(s, RSTART, RLENGTH); rest = substr(s, RLENGTH + 1)
  sub(/^[ \t]*\[[^]]*\]/, "", rest); gsub(/[ \t]/, "", rest)
  print name "\t" rest
}
# str_next(): moves the next quoted string off the front of the global line into the global str. It returns
# 0 when no string is left.
function str_next() {
  if (!match(line, /"[^"]*"|'[^']*'/)) return 0
  str = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
  return 1
}
# section(s): the name of a TOML table header line, as in "[tool.poetry.dependencies] # x" -> "tool.poetry.dependencies".
function section(s) {
  sub(/[ \t]*#.*/, "", s); gsub(/[][ \t]/, "", s)
  return s
}
# coord(s, free): prints "group:artifact<TAB>version" when s is a Maven coordinate. The two callers differ on
# purpose. A Gradle scan reads only dependency lines, so free = 1 accepts two parts and any version text, such
# as 1.+ or ${v}. A MODULE.bazel scan reads every string in the file, so free = 0 needs three parts and a plain
# version, or an ordinary string such as a label would match.
function coord(s, free,   c) {
  if (free) { if (s !~ /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+(:[^:]+)?$/) return }
  else if (s !~ /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.+-]+$/) return
  split(s, c, ":"); print c[1] ":" c[2] "\t" c[3]
}
# kvdep(line): a TOML line `name = "1.0"` or `name = { version = "1.0", ... }`.
function kvdep(line,   k, v, ver, s) {
  if (line !~ /^[ \t]*[A-Za-z0-9_."-]+[ \t]*=/) return
  k = line; sub(/[ \t]*=.*/, "", k); gsub(/^[ \t]+|"/, "", k)
  if (k == "python") return
  v = line; sub(/^[^=]*=[ \t]*/, "", v); ver = ""
  if (v ~ /^"/) { ver = v; sub(/^"/, "", ver); sub(/".*/, "", ver) }
  else if (match(v, /(^|[^-A-Za-z_])version[ \t]*=[ \t]*"[^"]*"/)) {
    s = substr(v, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s); ver = s
  }
  print k "\t" ver
}
EOF

read -r -d '' AWK_CARGO <<'EOF'
function flush() { if (subdep != "") print subdep "\t" subver; subdep = ""; subver = "" }
/^[ \t]*#/ { next }
/^[ \t]*\[/ {
  flush(); intbl = 0
  sec = section($0)
  if (sec ~ /(^|\.)(dev-|build-)?dependencies$/) intbl = 1
  else if (sec ~ /(^|\.)(dev-|build-)?dependencies\.[^.]+$/) { subdep = sec; sub(/.*\./, "", subdep) }
  next
}
intbl { kvdep($0); next }
subdep != "" && /^[ \t]*version[ \t]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*/, "", v); subver = v }
END { flush() }
EOF

read -r -d '' AWK_PYPROJECT <<'EOF'
/^[ \t]*#/ { next }
/^[ \t]*\[/ { sec = section($0); inlist = 0; next }
sec == "project" || sec == "project.optional-dependencies" || sec == "dependency-groups" {
  line = $0
  if (!inlist) {
    if (sec == "project" && line !~ /^[ \t]*dependencies[ \t]*=/) next
    if (line !~ /=[ \t]*\[/) next
    sub(/^[^=]*=[ \t]*\[/, "", line); inlist = 1
  }
  while (str_next()) req(str)
  if (line ~ /\]/) inlist = 0
  next
}
sec ~ /^tool\.poetry\.(dev-)?dependencies$|^tool\.poetry\.group\.[^.]+\.dependencies$/ { kvdep($0) }
EOF

read -r -d '' AWK_REQUIREMENTS <<'EOF'
/^[ \t]*(#|-)/ { next }
{ sub(/[ \t]+#.*/, ""); req($0) }
EOF

read -r -d '' AWK_GOMOD <<'EOF'
/^[ \t]*\/\// { next }
/^[ \t]*require[ \t]*\(/ { inreq = 1; next }
inreq && /^[ \t]*\)/ { inreq = 0; next }
inreq { sub(/\/\/.*/, ""); if (NF >= 2) print $1 "\t" $2; next }
/^[ \t]*require[ \t]+/ { sub(/\/\/.*/, ""); if (NF >= 3) print $2 "\t" $3 }
EOF

read -r -d '' AWK_BUILD <<'EOF'
{
  line = $0; sub(/#.*/, "", line)
  if (!inlist) {
    if (match(line, /(^|[^A-Za-z_])(deps|runtime_deps|exports)[ \t]*=[ \t]*\[/)) {
      line = substr(line, RSTART + RLENGTH); inlist = 1
    } else next
  }
  while (str_next()) if (str ~ /^@/) print str "\t"
  if (line ~ /\]/) inlist = 0
}
EOF

read -r -d '' AWK_MODULE <<'EOF'
function val(buf, key,   s) {
  if (!match(buf, "(^|[^A-Za-z_])" key "[ \t]*=[ \t]*\"[^\"]*\"")) return ""
  s = substr(buf, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s); return s
}
{ line = $0; sub(/#.*/, "", line) }
/bazel_dep[ \t]*\(/ { buf = ""; inb = 1 }
inb {
  buf = buf " " line
  if (line ~ /\)/) { inb = 0; n = val(buf, "name"); if (n != "") print n "\t" val(buf, "version") }
  next
}
{
  while (str_next()) coord(str, 0)
}
EOF

read -r -d '' AWK_POM <<'EOF'
function tag(line, n,   s) {
  if (!match(line, "<" n ">[^<]*</" n ">")) return ""
  s = substr(line, RSTART, RLENGTH); sub(/^<[^>]*>/, "", s); sub(/<.*/, "", s); return s
}
/<dependency>/ { indep = 1; g = ""; a = ""; v = ""; inex = 0 }
indep && /<\/exclusions>/ { inex = 0; next }
indep && /<exclusions>/ { inex = 1 }
indep && !inex {
  x = tag($0, "groupId"); if (x != "") g = x
  x = tag($0, "artifactId"); if (x != "") a = x
  x = tag($0, "version"); if (x != "") v = x
}
/<\/dependency>/ { if (indep && g != "" && a != "") print g ":" a "\t" v; indep = 0 }
EOF

read -r -d '' AWK_GRADLE <<'EOF'
/^[ \t]*[A-Za-z]*([Ii]mplementation|[Aa]pi|[Cc]ompileOnly|[Rr]untimeOnly|[Cc]ompile|[Rr]untime|[Pp]rocessor|kapt|ksp|classpath)[ \t(]/ {
  line = $0
  while (str_next()) coord(str, 1)
}
EOF

# parse_manifest <file>: prints one "name<TAB>version" line per dependency. It returns non-zero on failure.
# The case arms must cover every name in MANIFEST_NAMES. A name without an arm fails here, so the index shows
# error true for it, and names_cases in the smoke test checks that no listed name hits the default arm.
parse_manifest() {
  local f=$1
  case ${f##*/} in
    package.json) parse_package_json "$f" ;;
    Cargo.toml) awk "$AWK_LIB $AWK_CARGO" "$f" ;;
    pyproject.toml) awk "$AWK_LIB $AWK_PYPROJECT" "$f" ;;
    requirements*.txt) awk "$AWK_LIB $AWK_REQUIREMENTS" "$f" ;;
    go.mod) awk "$AWK_GOMOD" "$f" ;;
    BUILD | BUILD.bazel) awk "$AWK_LIB $AWK_BUILD" "$f" ;;
    MODULE.bazel) awk "$AWK_LIB $AWK_MODULE" "$f" ;;
    pom.xml) awk "$AWK_POM" "$f" ;;
    build.gradle | build.gradle.kts) awk "$AWK_LIB $AWK_GRADLE" "$f" ;;
    *) return 1 ;;
  esac
}

# parse_entry <path> <hash>: prints the index entry of one manifest as a {key, value} object on one line.
parse_entry() {
  local p=$1 h=$2 out err=false
  [ -n "${DEPS_INDEX_TRACE:-}" ] && echo "parse $p" >&2
  out=$(parse_manifest "$root/$p" 2>/dev/null) || { err=true; out=; }
  printf '%s' "$out" | jq -R -s -c --arg p "$p" --arg h "$h" --argjson e "$err" '
    {key: $p, value: {hash: $h, error: $e,
      deps: (split("\n") | map(select(length > 0) | split("\t")
             | {name: .[0], version: (if (.[1] // "") == "" then null else .[1] end)}) | unique)}}'
}

# build_index: the caller holds the lock. It parses only the manifests whose content hash changed.
build_index() {
  local work=$cache/deps.work.$$ old=$cache/deps.json p h tmp
  local -a paths=()
  sweep_dead_work_dirs
  mkdir -p "$work" || return 1
  while IFS= read -r -d '' p; do
    # The work files (paths, hashes, cur.tsv) hold one path per line, so a path with a newline would split.
    case $p in *$'\n'*) continue ;; esac
    is_manifest "${p##*/}" && [ -f "$root/$p" ] && paths+=("$p")
    lock_touch
  done < <(git -C "$root" ls-files -z)

  : > "$work/cur.tsv"
  if [ ${#paths[@]} -gt 0 ]; then
    printf '%s\n' "${paths[@]}" > "$work/paths"
    (cd "$root" && git hash-object --stdin-paths < "$work/paths") > "$work/hashes" || return 1
    paste "$work/paths" "$work/hashes" > "$work/cur.tsv"
  fi
  jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1]}) | from_entries' \
    "$work/cur.tsv" > "$work/cur.json" || return 1
  if jq -e '.schema == 1' "$old" >/dev/null 2>&1; then cp "$old" "$work/old.json"; else echo '{}' > "$work/old.json"; fi

  jq -n -r --slurpfile old "$work/old.json" --slurpfile cur "$work/cur.json" '
    ($old[0].manifests // {}) as $o
    | $cur[0] | to_entries[] | select(($o[.key].hash // "") != .value) | "\(.key)\t\(.value)"' > "$work/changed.tsv" || return 1
  : > "$work/new.jsonl"
  while IFS=$'\t' read -r p h; do
    parse_entry "$p" "$h" >> "$work/new.jsonl"
    lock_touch
  done < "$work/changed.tsv"

  [ -n "${DEPS_INDEX_TEST_DELAY:-}" ] && sleep "$DEPS_INDEX_TEST_DELAY"
  tmp=$cache/deps.json.tmp.$$
  # A steal can hand the lock to another build while this one runs. Its output is then stale, so discard it.
  [ "$(cat "$lock/owner" 2>/dev/null)" = "$$" ] || return 1
  jq -n -c --slurpfile old "$work/old.json" --slurpfile cur "$work/cur.json" --slurpfile new "$work/new.jsonl" '
    ($old[0].manifests // {}) as $o
    | {schema: 1,
       manifests: (($cur[0] | to_entries | map(select($o[.key].hash == .value) | {key: .key, value: $o[.key]}))
                   + $new | from_entries)}' > "$tmp" && mv "$tmp" "$old" || { rm -f "$tmp"; return 1; }
}

# read_index [path ...]: prints the entries of the manifests at the repo root and under each path. An absolute
# path is taken as it is. A relative path is taken from the caller's cwd, so "read b" from a/ means a/b. A
# trailing slash does not matter. The repo root, or "." from the root, selects the root manifests only. A path
# outside the repo is dropped. When every path is dropped nothing prints, so the caller falls back and does not
# take the root entries of this repo for those of another.
read_index() {
  local a pre=[] cwdpre
  local -a prefixes=()
  cwdpre=$(git rev-parse --show-prefix 2>/dev/null)
  for a in "$@"; do
    case $a in
      "$root") a=. ;;
      "$root"/*) a=${a#"$root"/} ;;
      /*) continue ;;
      .) a=$cwdpre ;;
      *) a=$cwdpre${a#./} ;;
    esac
    a=${a%/}
    [ -n "$a" ] || a=.
    prefixes+=("$a")
  done
  [ $# -eq 0 ] || [ ${#prefixes[@]} -gt 0 ] || return 0
  if [ ${#prefixes[@]} -gt 0 ]; then
    pre=$(printf '%s\n' "${prefixes[@]}" | jq -R -s -c 'split("\n")[:-1]') || return 1
  fi
  jq -c --argjson pre "$pre" '
    [.manifests | to_entries[]
     | select(($pre | length) == 0 or (.key | contains("/") | not)
              or (.key as $k | $pre | any(.[]; . as $p | $k | startswith($p + "/"))))
     | .key as $m | .value.deps[] | {name, version, manifest: $m}]' "$cache/deps.json"
}

# start_background: reads the hook input, enters its cwd and starts build detached. All three fds must be
# redirected, or the hook waits for the child. macOS has no setsid. The cd and the start stay on separate
# lines, because "cd && cmd &" backgrounds a subshell that keeps the hook stdout open.
start_background() {
  local self cwd
  self=$_here/${BASH_SOURCE[0]##*/}
  cwd=$(jq -r '.cwd // empty' 2>/dev/null) || return 0
  if [ -n "$cwd" ]; then
    cd "$cwd" 2>/dev/null || return 0
  fi
  nohup bash "$self" build </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null
  return 0
}

main() {
  case ${1:-} in
    names) printf '%s\n' $MANIFEST_NAMES; return 0 ;;
    build | read) ;;
    *) echo "usage: deps-index.sh build [--background] | read [path ...] | names" >&2; return 2 ;;
  esac
  [ "${BF_DEPS_HOOK:-}" = off ] && return 0
  command -v jq >/dev/null || return 0
  local mode=$1
  shift
  case $mode in
    build)
      if [ "${1:-}" = --background ]; then start_background; return 0; fi
      open_repo || return 0
      lock_acquire 0 || return 0
      build_index
      ;;
    read)
      open_repo || return 0
      lock_acquire 5 || return 0
      build_index && read_index "$@"
      ;;
  esac
  return 0
}

main "$@"
