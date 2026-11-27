#!/usr/bin/env bash
# Dependency index of a git repo: the declared dependencies of every tracked manifest, kept in
# .bf/cache/deps.json. The SessionStart hook starts the build in the background. Skills run read, which
# also builds and writes .bf/cache/, so an entry is never older than its manifest.
#
# Usage: deps-index.sh build [--background]   bring the index up to date. --background reads the hook
#                                             input JSON on stdin, takes cwd from it and returns at once.
#        deps-index.sh read [path ...]        build, then print a JSON array of {name, version, manifest}.
#                                             With paths, print only the manifests at the repo root, in the
#                                             dirs above each path and under each path. A relative path
#                                             starts at the cwd. "." at the repo root, or the root path,
#                                             prints only the root manifests.
#        deps-index.sh names                  print the manifest file names the index covers.
#        deps-index.sh parse-files <type> <file ...>   internal. build runs it through xargs on a batch.
# Env:   BF_DEPS_HOOK=off turns build and read off. names still prints. BF_DEPS_TRACE=1 prints
#        "parse <path>" on stderr for each manifest that is parsed. BF_DEPS_TEST_DELAY=<seconds> makes
#        build wait before it writes.
# Output: build prints nothing. read prints nothing when it fails, when jq is missing, when the directory is
#         not a git repo, or when every path is missing or outside the repo.
# Concurrency: there is no lock. Each build works in its own deps.work.<pid> dir and replaces deps.json with an
#         atomic mv, so a reader never sees a partial index. Two builds at once both parse, and the last mv wins.
#         Every entry keeps its manifest hash, so the next build parses again what an older winner missed.
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
# cd and pwd, not dirname, so it still works when PATH holds no dirname. A hook that cannot find its guard ends
# quietly.
_dir=${BASH_SOURCE[0]%/*}
[ "$_dir" != "${BASH_SOURCE[0]}" ] || _dir=.
_here=$(cd "$_dir" 2>/dev/null && pwd) || exit 0
source "$_here/dir-guard.sh" 2>/dev/null || exit 0

MANIFEST_NAMES="package.json BUILD.bazel BUILD MODULE.bazel pom.xml build.gradle build.gradle.kts pyproject.toml requirements*.txt go.mod Cargo.toml"

root=
cache=
work=
index=
mtype=

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
  work=$cache/deps.work.$$
  index=$work/index.json
  [ ! -L "$root/.bf" ] && [ ! -L "$cache" ] || return 1
  mkdir -p "$cache" 2>/dev/null && dir_guard_check "$cache" "$(id -u)" || return 1
  [ -e "$cache/.gitignore" ] || printf '*\n' > "$cache/.gitignore"
}

# sweep_dead_work_dirs: removes the deps.work.<pid> dirs of killed builds. kill -0 keeps the dir of a live
# build. The glob needs globbing, so it is turned on for the loop only.
sweep_dead_work_dirs() {
  local d
  set +f
  for d in "$cache"/deps.work.*; do
    [ -d "$d" ] && ! kill -0 "${d##*.}" 2>/dev/null && rm -rf "$d"
  done
  set -f
}

cleanup() {
  rm -rf "$work"
  rm -f "$cache/deps.json.tmp.$$"
}

parse_package_json() {
  jq -r '"\u0001\(input_filename)",
         ([.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
          | map(select(type == "object")) | .[] | to_entries[] | "\(.key)\t\(.value | tostring)")' "$@"
}

# The awk parsers print "name<TAB>version" lines and leave the version empty when it is unknown. BSD awk
# on macOS has no gensub and no IGNORECASE, so they use POSIX awk only. One awk run reads every changed file of
# a type, so each parser resets its state on the first line of a file (FNR == 1) and calls newfile, which
# prints a marker line with the file name. A Cargo dependency is flushed before the marker of the next file.
read -r -d '' AWK_LIB <<'EOF'
function newfile() { print "\001" FILENAME }
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
FNR == 1 { flush(); intbl = 0; sec = ""; newfile() }
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
FNR == 1 { sec = ""; inlist = 0; newfile() }
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
# Poetry declares the interpreter as a dependency (python = "^3.11"). It is not a library, so it is skipped.
sec ~ /^tool\.poetry\.(dev-)?dependencies$|^tool\.poetry\.group\.[^.]+\.dependencies$/ {
  if ($0 !~ /^[ \t]*"?python"?[ \t]*=/) kvdep($0)
}
EOF

read -r -d '' AWK_REQUIREMENTS <<'EOF'
FNR == 1 { newfile() }
/^[ \t]*(#|-)/ { next }
{ sub(/[ \t]+#.*/, ""); req($0) }
EOF

read -r -d '' AWK_GOMOD <<'EOF'
FNR == 1 { inreq = 0; newfile() }
/^[ \t]*\/\// { next }
/^[ \t]*require[ \t]*\(/ { inreq = 1; next }
inreq && /^[ \t]*\)/ { inreq = 0; next }
inreq { sub(/\/\/.*/, ""); if (NF >= 2) print $1 "\t" $2; next }
/^[ \t]*require[ \t]+/ { sub(/\/\/.*/, ""); if (NF >= 3) print $2 "\t" $3 }
EOF

read -r -d '' AWK_BUILD <<'EOF'
FNR == 1 { inlist = 0; newfile() }
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
FNR == 1 { buf = ""; inb = 0; newfile() }
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
FNR == 1 { indep = 0; inex = 0; skip = 0; newfile() }
function tag(line, n,   s) {
  if (!match(line, "<" n ">[^<]*</" n ">")) return ""
  s = substr(line, RSTART, RLENGTH); sub(/^<[^>]*>/, "", s); sub(/<.*/, "", s); return s
}
# A <dependencyManagement> entry only pins a version, and a <plugin> dependency is on the plugin classpath. Neither
# is a dependency of the module, so skip counts the open blocks of both kinds.
/<dependencyManagement>/ { skip++ }
/<plugin>/ { skip++ }
/<dependency>/ && !skip { indep = 1; g = ""; a = ""; v = ""; inex = 0 }
indep && /<\/exclusions>/ { inex = 0; next }
indep && /<exclusions>/ { inex = 1 }
indep && !inex {
  x = tag($0, "groupId"); if (x != "") g = x
  x = tag($0, "artifactId"); if (x != "") a = x
  x = tag($0, "version"); if (x != "") v = x
}
/<\/dependency>/ { if (indep && g != "" && a != "") print g ":" a "\t" v; indep = 0 }
/<\/dependencyManagement>/ { if (skip > 0) skip-- }
/<\/plugin>/ { if (skip > 0) skip-- }
EOF

read -r -d '' AWK_GRADLE <<'EOF'
FNR == 1 { newfile() }
/^[ \t]*[A-Za-z]*([Ii]mplementation|[Aa]pi|[Cc]ompileOnly|[Rr]untimeOnly|[Cc]ompile|[Rr]untime|[Pp]rocessor|kapt|ksp|classpath)[ \t(]/ {
  line = $0
  while (str_next()) coord(str, 1)
}
EOF

# manifest_type <name>: sets mtype to the parser key of a manifest file name. It prints nothing, so the build
# loop needs no subshell per file. It returns non-zero for a name with no parser. The case arms must cover
# every name in MANIFEST_NAMES. A name without an arm gets error true in the index, and names_parse_cases in
# the smoke test checks that no listed name hits the default arm.
manifest_type() {
  case $1 in
    package.json) mtype=package ;;
    Cargo.toml) mtype=cargo ;;
    pyproject.toml) mtype=pyproject ;;
    requirements*.txt) mtype=requirements ;;
    go.mod) mtype=gomod ;;
    BUILD | BUILD.bazel) mtype=build ;;
    MODULE.bazel) mtype=module ;;
    pom.xml) mtype=pom ;;
    build.gradle | build.gradle.kts) mtype=gradle ;;
    *) return 1 ;;
  esac
}

# parse_files <type> <file ...>: runs the parser of the type on the files and prints a marker line (\001 and the
# file name) per file, then its "name<TAB>version" lines. It returns non-zero when the parser fails on any file.
parse_files() {
  local t=$1 prog
  shift
  case $t in
    package) parse_package_json "$@"; return ;;
    cargo) prog=$AWK_CARGO ;;
    pyproject) prog=$AWK_PYPROJECT ;;
    requirements) prog=$AWK_REQUIREMENTS ;;
    gomod) prog=$AWK_GOMOD ;;
    build) prog=$AWK_BUILD ;;
    module) prog=$AWK_MODULE ;;
    pom) prog=$AWK_POM ;;
    gradle) prog=$AWK_GRADLE ;;
    *) return 1 ;;
  esac
  awk "$AWK_LIB $prog" "$@"
}

# parse_type <type>: parses the files listed in $work/list.<type> and prints their marker and dependency lines.
# A process start costs about 7 ms on macOS, so xargs runs one parser over many files. When that run fails,
# for example on one invalid package.json, each file runs alone, and a file that still fails gets an
# "\002<path>" error line in place of its dependencies.
parse_type() {
  local t=$1 f list=$work/list.$t
  if (cd "$root" && xargs -0 bash "$_here/${BASH_SOURCE[0]##*/}" parse-files "$t" < "$list") > "$work/out" 2>/dev/null; then
    cat "$work/out"
    return 0
  fi
  while IFS= read -r -d '' f; do
    if (cd "$root" && parse_files "$t" "$f") > "$work/one" 2>/dev/null; then
      cat "$work/one"
    else
      printf '\002%s\n' "$f"
    fi
  done < "$list"
}

# list_manifests: writes $work/cur.json, the content hash of every tracked manifest, keyed by path.
list_manifests() {
  local p
  local -a paths=()
  while IFS= read -r -d '' p; do
    # The work files (paths, hashes, cur.tsv) hold one path per line, so a path with a newline would split.
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
    "$work/cur.tsv" > "$work/cur.json"
}

# changed_manifests <old>: copies the old index to $work/old.json, or an empty one when it is missing or has
# another schema. Then it writes $work/changed.tsv, a "path<TAB>hash" line per manifest whose hash changed.
changed_manifests() {
  if jq -e '.schema == 1' "$1" >/dev/null 2>&1; then cp "$1" "$work/old.json"; else echo '{}' > "$work/old.json"; fi
  jq -n -r --slurpfile old "$work/old.json" --slurpfile cur "$work/cur.json" '
    ($old[0].manifests // {}) as $o
    | $cur[0] | to_entries[] | select(($o[.key].hash // "") != .value) | "\(.key)\t\(.value)"' > "$work/changed.tsv"
}

# parse_changed: parses the manifests in $work/changed.tsv and writes their entries to $work/new.json.
# Rows: a manifest line ("\003path<TAB>hash<TAB>error") per changed manifest, then the parser output of each
# type. A marker line (\001) starts the dependencies of a file, and an error line (\002) marks a file the parser
# could not read. Each kind starts with a control character, because a dependency line can start with any
# name, "M" included.
parse_changed() {
  local p h t types=
  while IFS=$'\t' read -r p h; do
    [ -n "${BF_DEPS_TRACE:-}" ] && echo "parse $p" >&2
    if manifest_type "${p##*/}"; then
      t=$mtype
      printf '\003%s\t%s\tfalse\n' "$p" "$h"
      # ./ keeps awk from reading a path that starts with - as an option.
      printf './%s\0' "$p" >> "$work/list.$t"
      case " $types " in *" $t "*) ;; *) types="$types $t" ;; esac
    else
      printf '\003%s\t%s\ttrue\n' "$p" "$h"
    fi
  done < "$work/changed.tsv" > "$work/rows.tsv"
  for t in $types; do parse_type "$t"; done >> "$work/rows.tsv"
  jq -R -s -c '
    def rel: ltrimstr("./");
    reduce (split("\n")[] | select(length > 0)) as $l ({cur: null, m: {}};
      if ($l | startswith("\u0001")) then .cur = ($l[1:] | rel)
      elif ($l | startswith("\u0002")) then .m[$l[1:] | rel] |= (.error = true | .deps = []) | .cur = null
      elif ($l | startswith("\u0003")) then ($l[1:] | split("\t")) as $r
        | .m[$r[0]] = {hash: $r[1], error: ($r[2] == "true"), deps: []}
      elif .cur == null then .
      else ($l | split("\t")) as $r
        | .m[.cur].deps += [{name: $r[0], version: (if ($r[1] // "") == "" then null else $r[1] end)}] end)
    | .m | map_values(.deps |= unique)' "$work/rows.tsv" > "$work/new.json"
}

# write_index <old>: merges the unchanged old entries with the new ones into $index and moves a copy over the
# old index. The mv is atomic, so a reader never sees a partial file.
write_index() {
  local tmp=$cache/deps.json.tmp.$$
  jq -n -c --slurpfile old "$work/old.json" --slurpfile cur "$work/cur.json" --slurpfile new "$work/new.json" '
    ($old[0].manifests // {}) as $o
    | {schema: 1,
       manifests: (($cur[0] | to_entries | map(select($o[.key].hash == .value) | {key: .key, value: $o[.key]}))
                   + ($new[0] | to_entries) | from_entries)}' > "$index" || return 1
  cp "$index" "$tmp" && mv "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

# build_index: parses only the manifests whose content hash changed. It keeps its result in $index until the
# EXIT trap, so the caller can pass that file to read_index. read then prints the index this build made, even
# when another build wins the mv.
build_index() {
  local old=$cache/deps.json
  sweep_dead_work_dirs
  # A killed build with the same pid can leave this dir behind, and its list files would be parsed again.
  rm -rf "$work"
  mkdir -p "$work" || return 1
  trap cleanup EXIT
  list_manifests || return 1
  changed_manifests "$old" || return 1
  parse_changed || return 1
  [ -n "${BF_DEPS_TEST_DELAY:-}" ] && sleep "$BF_DEPS_TEST_DELAY"
  write_index "$old"
}

# read_index <index> [path ...]: prints from the index file the entries of the manifests at the repo root, in
# the dirs above each path and under each path. So a source dir or file inside a package selects that package.
# A relative path starts at the cwd. Each path is resolved with cd and pwd -P, so "..", "." and symlinks work,
# and a file path stands for its directory. The repo root selects the root manifests only. A path that is
# missing or outside the repo is dropped. When every path is dropped nothing prints, so the caller falls back
# and does not take the root entries for those of another tree.
read_index() {
  local index=$1 a d rootp pre=[]
  shift
  local -a prefixes=()
  rootp=$(cd "$root" && pwd -P) || return 1
  for a in "$@"; do
    [ -f "$a" ] && { case $a in */*) a=${a%/*} ;; *) a=. ;; esac; }
    d=$(cd "$a" 2>/dev/null && pwd -P) || continue
    case $d in
      "$rootp") prefixes+=(.) ;;
      "$rootp"/*) prefixes+=("${d#"$rootp"/}") ;;
    esac
  done
  [ $# -eq 0 ] || [ ${#prefixes[@]} -gt 0 ] || return 0
  if [ ${#prefixes[@]} -gt 0 ]; then
    pre=$(printf '%s\n' "${prefixes[@]}" | jq -R -s -c 'split("\n")[:-1]') || return 1
  fi
  jq -c --argjson pre "$pre" '
    [.manifests | to_entries[]
     # Index keys never start with "./", because rel in parse_changed strips it, so the prefix "." selects
     # only the root.
     | (.key | split("/") | .[:-1] | join("/")) as $d
     | select(($pre | length) == 0 or $d == ""
              or (.key as $k | $pre | any(.[]; . as $p | ($k | startswith($p + "/")) or ($p | startswith($d + "/")))))
     | .key as $m | .value.deps[] | {name, version, manifest: $m}]' "$index"
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
    parse-files) shift; parse_files "$@"; return ;;
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
      build_index
      ;;
    read)
      open_repo || return 0
      build_index && read_index "$index" "$@"
      ;;
  esac
  return 0
}

main "$@"
