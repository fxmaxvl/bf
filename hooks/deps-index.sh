#!/usr/bin/env bash
# Dependency index of a git repo: the declared dependencies of every tracked manifest, kept in
# .bf/cache/deps.json. The SessionStart hook starts the build in the background. Skills run read, which
# also builds and writes .bf/cache/, so an entry is never older than its manifest.
#
# Usage: deps-index.sh build [--background]   bring the index up to date. --background reads the hook
#                                             input JSON on stdin, takes cwd from it and returns at once.
#        deps-index.sh read [path ...]        build, then print a JSON array of {name, version, manifest}.
#                                             With paths, print only the manifests at the repo root and
#                                             under those paths.
#        deps-index.sh names                  print the manifest file names the index covers.
# Env:   BF_DEPS_HOOK=off turns every mode off. DEPS_INDEX_TRACE=1 prints "parse <path>" on stderr for each
#        manifest that is parsed. DEPS_INDEX_TEST_DELAY=<seconds> makes build wait before it writes.
# Output: build prints nothing. read prints nothing when it fails, when jq is missing, when the directory is
#         not a git repo, or when a live build holds the lock for more than 5 seconds.
# Limits: only tracked manifests count, so a new manifest is invisible until it is staged. BUILD files keep
#         external labels only (@repo//...). The awk parsers read the common table shapes and are best
#         effort. A manifest that fails to parse gets error true and no dependencies.
set -uo pipefail
set -f

MANIFEST_NAMES="package.json BUILD.bazel BUILD MODULE.bazel pom.xml build.gradle build.gradle.kts pyproject.toml requirements*.txt go.mod Cargo.toml"

root=
cache=
lock=

is_manifest() {
  local pat
  for pat in $MANIFEST_NAMES; do
    case $1 in $pat) return 0 ;; esac
  done
  return 1
}

# Same symlink and owner checks as prose_record_dir_ensure in prose-lib.sh. It leaves out the mode check,
# because an existing .bf/cache with mode 755 must work.
open_repo() {
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  cache=$root/.bf/cache
  lock=$cache/deps.lock
  [ ! -L "$root/.bf" ] && [ ! -L "$cache" ] || return 1
  mkdir -p "$cache" 2>/dev/null && [ -O "$cache" ] || return 1
  [ -e "$cache/.gitignore" ] || printf '*\n' > "$cache/.gitignore"
}

# lock_acquire <wait_seconds>: mkdir is atomic and flock(1) is missing on macOS. A lock older than 60 seconds
# belongs to a killed build. The EXIT trap is set only after mkdir succeeds, or a skipped caller would delete
# the lock of the live build.
lock_acquire() {
  local wait=$1 waited=0 started now
  while :; do
    if mkdir "$lock" 2>/dev/null; then
      date +%s > "$lock/started"
      trap 'rm -rf "$lock"' EXIT
      return 0
    fi
    now=$(date +%s)
    started=$(cat "$lock/started" 2>/dev/null)
    if [ -z "$started" ]; then
      [ -d "$lock" ] && printf '%s\n' "$now" > "$lock/started" 2>/dev/null
      started=$now
    fi
    if [ $((now - started)) -gt 60 ]; then
      rm -rf "$lock"
      continue
    fi
    [ "$waited" -ge "$wait" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
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
  sec = $0; sub(/[ \t]*#.*/, "", sec); gsub(/[][ \t]/, "", sec)
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
/^[ \t]*\[/ { sec = $0; sub(/[ \t]*#.*/, "", sec); gsub(/[][ \t]/, "", sec); inlist = 0; next }
sec == "project" || sec == "project.optional-dependencies" || sec == "dependency-groups" {
  line = $0
  if (!inlist) {
    if (sec == "project" && line !~ /^[ \t]*dependencies[ \t]*=/) next
    if (line !~ /=[ \t]*\[/) next
    sub(/^[^=]*=[ \t]*\[/, "", line); inlist = 1
  }
  while (match(line, /"[^"]*"|'[^']*'/)) {
    s = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH); req(s)
  }
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
  while (match(line, /"[^"]*"|'[^']*'/)) {
    s = substr(line, RSTART + 1, RLENGTH - 2)
    if (s ~ /^@/) print s "\t"
    line = substr(line, RSTART + RLENGTH)
  }
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
  while (match(line, /"[^"]*"/)) {
    s = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
    if (s ~ /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.+-]+$/) {
      split(s, c, ":"); print c[1] ":" c[2] "\t" c[3]
    }
  }
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
  while (match(line, /"[^"]*"|'[^']*'/)) {
    s = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
    if (s ~ /^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+(:[^:]+)?$/) {
      split(s, c, ":"); print c[1] ":" c[2] "\t" c[3]
    }
  }
}
EOF

# parse_manifest <file>: prints one "name<TAB>version" line per dependency. It returns non-zero on failure.
parse_manifest() {
  local f=$1
  case ${f##*/} in
    package.json) parse_package_json "$f" ;;
    Cargo.toml) awk "$AWK_LIB $AWK_CARGO" "$f" ;;
    pyproject.toml) awk "$AWK_LIB $AWK_PYPROJECT" "$f" ;;
    requirements*.txt) awk "$AWK_LIB $AWK_REQUIREMENTS" "$f" ;;
    go.mod) awk "$AWK_GOMOD" "$f" ;;
    BUILD | BUILD.bazel) awk "$AWK_BUILD" "$f" ;;
    MODULE.bazel) awk "$AWK_MODULE" "$f" ;;
    pom.xml) awk "$AWK_POM" "$f" ;;
    build.gradle | build.gradle.kts) awk "$AWK_GRADLE" "$f" ;;
    *) return 0 ;;
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
  local work=$lock/work old=$cache/deps.json p h tmp
  local -a paths=()
  mkdir -p "$work" || return 1
  while IFS= read -r -d '' p; do
    case $p in *$'\n'*) continue ;; esac
    is_manifest "${p##*/}" && [ -f "$root/$p" ] && paths+=("$p")
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
  done < "$work/changed.tsv"

  [ -n "${DEPS_INDEX_TEST_DELAY:-}" ] && sleep "$DEPS_INDEX_TEST_DELAY"
  tmp=$cache/deps.json.tmp.$$
  jq -n -c --slurpfile old "$work/old.json" --slurpfile cur "$work/cur.json" --slurpfile new "$work/new.jsonl" '
    ($old[0].manifests // {}) as $o
    | {schema: 1,
       manifests: (($cur[0] | to_entries | map(select($o[.key].hash == .value) | {key: .key, value: $o[.key]}))
                   + $new | from_entries)}' > "$tmp" && mv "$tmp" "$old" || { rm -f "$tmp"; return 1; }
}

# read_index [path ...]: prints the entries of the manifests at the repo root and under each path. A path
# may be absolute or start with ./, and a trailing slash does not matter.
read_index() {
  local a pre=[]
  local -a prefixes=()
  for a in "$@"; do
    a=${a#"$root"/}; a=${a#./}; a=${a%/}
    prefixes+=("$a")
  done
  if [ ${#prefixes[@]} -gt 0 ]; then
    pre=$(printf '%s\n' "${prefixes[@]}" | jq -R -s -c 'split("\n")[:-1]') || return 1
  fi
  jq -c --argjson pre "$pre" '
    [.manifests | to_entries[]
     | select(($pre | length) == 0 or (.key | contains("/") | not)
              or (.key as $k | $pre | any(.[]; . as $p | $k | startswith($p + "/"))))
     | .key as $m | .value.deps[] | {name, version, manifest: $m}]' "$cache/deps.json"
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
