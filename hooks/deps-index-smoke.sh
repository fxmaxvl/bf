#!/usr/bin/env bash
# Smoke test for deps-index.sh: parsers, incremental build, read, concurrent builds, kill switch, background start and
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
  read_cases
  e2e_cases
  registration_cases
  names_cases
  names_parse_cases
  batch_cases

  [ "$fails" = 0 ]
}

guard_cases() {
  local out plain
  plain=$tmp/plain
  mkdir -p "$plain"
  out=$(cd "$plain" && bash "$script" build 2>&1); rc=$?
  eq "not a git repo: exit and output" "$rc:$out" "0:"
  eq "not a git repo: no cache" "$([ -e "$plain/.bf/cache" ] && echo yes || echo no)" no

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  out=$(cd "$repo" && env PATH=/nonexistent /bin/bash "$script" build 2>&1); rc=$?
  eq "no jq on PATH: exit and output" "$rc:$out" "0:"
  eq "no jq on PATH: no index" "$([ -e "$repo/.bf/cache/deps.json" ] && echo yes || echo no)" no

  out=$(cd "$repo" && BF_DEPS_HOOK=off bash "$script" build 2>&1); rc=$?
  eq "BF_DEPS_HOOK=off: exit and output" "$rc:$out" "0:"
  eq "BF_DEPS_HOOK=off: no cache dir" "$([ -e "$repo/.bf/cache" ] && echo yes || echo no)" no
}

unit_cases() {
  ctx_init
  put package.json <<'EOF'
{"name":"x","dependencies":{"a":"^1.0.0"},"devDependencies":{"b":"~2.0"},
 "peerDependencies":{"c":">=3"},"optionalDependencies":{"d":"4.0.0"}}
EOF
  idx build
  eq "package.json: four dependency tables" "$(deps_of package.json)" "false a=^1.0.0,b=~2.0,c=>=3,d=4.0.0"

  ctx_init
  put package.json <<'EOF'
{ not json
EOF
  idx build
  eq "package.json: invalid JSON gives error and no deps" "$(deps_of package.json)" "true "

  ctx_init
  put Cargo.toml <<'EOF'
[package]
name = "x"
version = "0.1.0"

[dependencies]
serde = "1.0"
tokio = { version = "1.2", features = ["full"] }
local = { path = "../local" }

[dev-dependencies]
rand = "0.8"

[build-dependencies]
cc = "1.0"

[workspace.dependencies]
anyhow = "1"

[dependencies.regex]
version = "1.5"
EOF
  idx build
  eq "Cargo.toml: dependency tables and inline tables" "$(deps_of Cargo.toml)" \
    "false anyhow=1,cc=1.0,local=null,rand=0.8,regex=1.5,serde=1.0,tokio=1.2"

  ctx_init
  put pyproject.toml <<'EOF'
[project]
name = "x"
version = "1.0"
dependencies = [
  "requests>=2.31",
  "uvicorn[standard]==0.30",  # server
  'pyyaml',
]

[project.optional-dependencies]
dev = ["pytest>=8"]

[tool.poetry.dependencies]
python = "^3.11"
flask = "^1.2"
httpx = { version = "^0.27", extras = ["http2"] }
EOF
  idx build
  eq "pyproject.toml: PEP 621 and poetry" "$(deps_of pyproject.toml)" \
    "false flask=^1.2,httpx=^0.27,pytest=>=8,pyyaml=null,requests=>=2.31,uvicorn===0.30"

  ctx_init
  put requirements.txt <<'EOF'
# comment
requests==2.31.0
flask>=2.0  # inline comment
numpy
-r other.txt
-e .
--index-url https://example.com
pandas==2.0 ; python_version >= "3.9"
EOF
  put requirements-dev.txt <<'EOF'
pytest>=8
EOF
  idx build
  eq "requirements.txt: specifiers, comments, options, markers" "$(deps_of requirements.txt)" \
    "false flask=>=2.0,numpy=null,pandas===2.0,requests===2.31.0"
  eq "requirements-dev.txt is a manifest" "$(deps_of requirements-dev.txt)" "false pytest=>=8"

  ctx_init
  put go.mod <<'EOF'
module example.com/x

go 1.21

require (
	github.com/a/b v1.2.3
	github.com/c/d v0.1.0 // indirect
)

require github.com/e/f v2.0.0

replace github.com/a/b => ../b
EOF
  idx build
  eq "go.mod: block, single line and indirect" "$(deps_of go.mod)" \
    "false github.com/a/b=v1.2.3,github.com/c/d=v0.1.0,github.com/e/f=v2.0.0"

  ctx_init
  put BUILD.bazel <<'EOF'
java_library(
    name = "lib",
    deps = [
        "//internal:util",
        "@maven//:com_google_guava_guava",
        ":local",
        "@maven//:com_google_guava_guava",
    ],
    runtime_deps = ["@maven//:org_slf4j_slf4j_api"],
    exports = ["@repo"],
)
EOF
  put sub/BUILD <<'EOF'
py_library(name = "p", deps = ["@pip//numpy", "//x:y"])
EOF
  idx build
  eq "BUILD.bazel: external labels, deduplicated" "$(deps_of BUILD.bazel)" \
    "false @maven//:com_google_guava_guava=null,@maven//:org_slf4j_slf4j_api=null,@repo=null"
  eq "BUILD: single-line deps" "$(deps_of sub/BUILD)" "false @pip//numpy=null"

  ctx_init
  put MODULE.bazel <<'EOF'
module(name = "x")
bazel_dep(name = "rules_java", version = "7.1.0")
bazel_dep(
    version = "1.2",
    name = "abseil-cpp",
    repo_name = "com_google_absl",
)
maven.install(artifacts = [
    "com.google.guava:guava:32.1.2-jre",
    "org.slf4j:slf4j-api:2.0.9",
])
EOF
  idx build
  eq "MODULE.bazel: bazel_dep in any order and maven artifacts" "$(deps_of MODULE.bazel)" \
    "false abseil-cpp=1.2,com.google.guava:guava=32.1.2-jre,org.slf4j:slf4j-api=2.0.9,rules_java=7.1.0"

  ctx_init
  put pom.xml <<'EOF'
<project>
  <parent><groupId>org.p</groupId><artifactId>parent</artifactId><version>1</version></parent>
  <dependencies>
    <dependency>
      <groupId>com.fasterxml</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.15.0</version>
      <exclusions>
        <exclusion><groupId>x</groupId><artifactId>y</artifactId></exclusion>
      </exclusions>
    </dependency>
    <dependency><groupId>org.junit</groupId><artifactId>junit</artifactId><version>${junit.version}</version></dependency>
    <dependency>
      <groupId>org.managed</groupId>
      <artifactId>m</artifactId>
    </dependency>
  </dependencies>
</project>
EOF
  idx build
  eq "pom.xml: coordinates, property version, exclusions ignored" "$(deps_of pom.xml)" \
    'false com.fasterxml:jackson-databind=2.15.0,org.junit:junit=${junit.version},org.managed:m=null'

  ctx_init
  put build.gradle <<'EOF'
dependencies {
    implementation 'com.google.guava:guava:32.1.2-jre'
    api("org.slf4j:slf4j-api:2.0.9")
    testImplementation "junit:junit:4.13"
    compileOnly 'org.projectlombok:lombok'
    id 'java'
}
EOF
  put sub/build.gradle.kts <<'EOF'
dependencies {
    runtimeOnly("com.h2database:h2:2.2.224")
}
EOF
  idx build
  eq "build.gradle: configurations with and without parens" "$(deps_of build.gradle)" \
    "false com.google.guava:guava=32.1.2-jre,junit:junit=4.13,org.projectlombok:lombok=null,org.slf4j:slf4j-api=2.0.9"
  eq "build.gradle.kts: runtimeOnly" "$(deps_of sub/build.gradle.kts)" "false com.h2database:h2=2.2.224"
}

integration_cases() {
  local t

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  idx build
  t=$(BF_DEPS_TRACE=1 idx build 2>&1)
  eq "incremental: unchanged manifest is not parsed again" "$t" ""

  printf '{"dependencies":{"a":"2"}}\n' > "$repo/package.json"
  t=$(BF_DEPS_TRACE=1 idx build 2>&1)
  eq "incremental: changed manifest is parsed again" "$t" "parse package.json"
  eq "incremental: changed manifest has the new version" "$(deps_of package.json)" "false a=2"

  git -C "$repo" rm -q -f package.json
  idx build
  eq "incremental: removed manifest is dropped" "$(deps_of package.json)" missing

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
  eq "file deleted in the work tree: build exits 0" "$rc" 0
  eq "file deleted in the work tree: entry dropped" "$(deps_of sub/package.json)" missing
  eq "file deleted in the work tree: other entry kept" "$(deps_of package.json)" "false a=1"
  eq "index parses with jq" "$(jq -e '.schema == 1' "$repo/.bf/cache/deps.json" >/dev/null 2>&1 && echo yes)" yes
  eq "no temp file remains" "$(ls "$repo/.bf/cache" | grep -c 'deps.json.tmp')" 0
  eq "cache .gitignore holds *" "$(cat "$repo/.bf/cache/.gitignore")" '*'
  eq "no work dir remains after a build" "$(ls -A "$repo/.bf/cache" | grep -c 'deps[.]work')" 0

  # A killed build leaves its work dir. The next build removes it.
  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  mkdir -p "$repo/.bf/cache/deps.work.99999999"
  idx build
  eq "dead build: its work dir is swept" "$([ -e "$repo/.bf/cache/deps.work.99999999" ] && echo yes || echo no)" no
  eq "dead build: the index is built" "$(deps_of package.json)" "false a=1"

  # Builds at once: each parses in its own work dir and the index stays whole.
  local pa i
  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  (cd "$repo" && BF_DEPS_TEST_DELAY=2 exec bash "$script" build) & pa=$!
  out=$(idx read)
  eq "read during a slow build prints its own result" "$out" '[{"name":"a","version":"1","manifest":"package.json"}]'
  wait "$pa"
  for i in 1 2 3 4 5 6 7 8; do
    (cd "$repo" && bash "$script" build) &
  done
  wait
  eq "8 builds at once: index is valid" "$(deps_of package.json)" "false a=1"
  eq "8 builds at once: nothing left over" "$(ls -A "$repo/.bf/cache" | grep -c 'deps[.]\(work\|json[.]tmp\)')" 0

  ctx_init
  mkdir -p -m 755 "$repo/.bf/cache"
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  idx build
  eq "existing cache dir with mode 755 works" "$(deps_of package.json)" "false a=1"
}

read_cases() {
  local out

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  out=$(idx read)
  eq "read on a fresh repo builds and prints entries" "$out" '[{"name":"a","version":"1","manifest":"package.json"}]'

  printf '{"dependencies":{"a":"2"}}\n' > "$repo/package.json"
  out=$(idx read)
  eq "read after a manifest edit prints the new version" "$out" '[{"name":"a","version":"2","manifest":"package.json"}]'

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"root":"1"}}
EOF
  put services/api/package.json <<'EOF'
{"dependencies":{"api":"1"}}
EOF
  put services/api/deep/package.json <<'EOF'
{"dependencies":{"deep":"1"}}
EOF
  put services/apiary/package.json <<'EOF'
{"dependencies":{"apiary":"1"}}
EOF
  put services/web/package.json <<'EOF'
{"dependencies":{"web":"1"}}
EOF
  out=$(idx read | jq -r 'map(.name) | sort | join(",")')
  eq "read without a prefix prints every manifest" "$out" "api,apiary,deep,root,web"
  out=$(idx read services/api | jq -r 'map(.name) | sort | join(",")')
  eq "read with a prefix: root and that tree only" "$out" "api,deep,root"
  out=$(idx read services/api/ | jq -r 'map(.name) | sort | join(",")')
  eq "read with a trailing slash" "$out" "api,deep,root"
  out=$(idx read "$repo/services/api" | jq -r 'map(.name) | sort | join(",")')
  eq "read with an absolute prefix" "$out" "api,deep,root"
  out=$(idx read /somewhere/else/repo)
  eq "read with a path outside the repo prints nothing" "$out" ""
  out=$(idx read /somewhere/else/repo services/web | jq -r 'map(.name) | sort | join(",")')
  eq "read drops the outside path and keeps the other" "$out" "root,web"
  out=$(idx read ./services/api | jq -r 'map(.name) | sort | join(",")')
  eq "read with a ./ prefix" "$out" "api,deep,root"
  out=$(idx read services/api services/web | jq -r 'map(.name) | sort | join(",")')
  eq "read with two prefixes" "$out" "api,deep,root,web"
  out=$(idx read . | jq -r 'map(.name) | sort | join(",")')
  eq "read . from the root prints the root manifests only" "$out" "root"
  out=$(idx read "$repo" | jq -r 'map(.name) | sort | join(",")')
  eq "read of the repo root path prints the root manifests only" "$out" "root"
  out=$(cd "$repo/services" && bash "$script" read api | jq -r 'map(.name) | sort | join(",")')
  eq "read with a relative path from a subdirectory" "$out" "api,deep,root"
  out=$(cd "$repo/services/api" && bash "$script" read . | jq -r 'map(.name) | sort | join(",")')
  eq "read . from a subdirectory: root and that tree" "$out" "api,deep,root"
  out=$(cd "$repo/services/api" && bash "$script" read ../web | jq -r 'map(.name) | sort | join(",")')
  eq "read ../ from a subdirectory: the sibling tree" "$out" "root,web"
  out=$(cd "$repo/services/api" && bash "$script" read ../..  | jq -r 'map(.name) | sort | join(",")')
  eq "read ../.. to the root prints the root manifests only" "$out" "root"
  out=$(cd "$repo/services/api" && bash "$script" read ../../..)
  eq "read ../ past the root prints nothing" "$out" ""
  out=$(idx read services/missing)
  eq "read of a missing path prints nothing" "$out" ""
  out=$(idx read services/api/package.json | jq -r 'map(.name) | sort | join(",")')
  eq "read of a file path selects its directory" "$out" "api,deep,root"
  mkdir -p "$repo/services/api/src"
  : > "$repo/services/api/src/x.js"
  out=$(idx read services/api/src | jq -r 'map(.name) | sort | join(",")')
  eq "read of a source dir includes the package above it" "$out" "api,root"
  out=$(idx read services/api/src/x.js | jq -r 'map(.name) | sort | join(",")')
  eq "read of a source file includes the package above it" "$out" "api,root"

  out=$(cd "$repo" && BF_DEPS_HOOK=off bash "$script" read 2>&1); rc=$?
  eq "read with BF_DEPS_HOOK=off prints nothing" "$rc:$out" "0:"
  out=$(cd "$tmp/plain" && bash "$script" read 2>&1); rc=$?
  eq "read outside a repo prints nothing" "$rc:$out" "0:"
  out=$(cd "$repo" && env PATH=/nonexistent /bin/bash "$script" read 2>&1); rc=$?
  eq "read without jq prints nothing" "$rc:$out" "0:"
}

e2e_cases() {
  local cmd out start elapsed i

  cmd=$(hook_command)
  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  start=$(date +%s)
  out=$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$repo" \
    | BF_DEPS_TEST_DELAY=3 bash -c "$cmd"); rc=$?
  elapsed=$(($(date +%s) - start))
  eq "hook command: exit and stdout" "$rc:$out" "0:"
  eq "hook command returns within 1 second while the build is slow" "$([ "$elapsed" -le 1 ] && echo yes || echo "no ($elapsed s)")" yes
  for i in $(seq 1 20); do [ -f "$repo/.bf/cache/deps.json" ] && break; sleep 0.5; done
  eq "hook command: the index appears afterwards" "$(deps_of package.json)" "false a=1"

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  out=$(printf '{"cwd":"%s"}' "$repo" | BF_DEPS_HOOK=off bash -c "$cmd"); rc=$?
  sleep 1
  eq "BF_DEPS_HOOK=off: hook returns and writes nothing" "$rc:$out:$([ -e "$repo/.bf/cache" ] && echo yes || echo no)" "0::no"

  out=$(cd "$repo" && printf 'not json' | bash -c "$cmd"); rc=$?
  sleep 1
  eq "input that is not JSON: exit 0 and nothing written" "$rc:$out:$([ -e "$repo/.bf/cache" ] && echo yes || echo no)" "0::no"
}

registration_cases() {
  local cfg=$(dirname "$script")/hooks.json
  eq "hooks.json: one startup|resume|clear group runs deps-index.sh with timeout 5" \
    "$(jq -r '[.hooks.SessionStart[] | select(.matcher == "startup|resume|clear") | .hooks[]
               | select(.command | test("hooks/deps-index[.]sh\" build --background")) | .timeout] | join(",")' "$cfg")" 5
  eq "hooks.json: the compact prose group stays registered" \
    "$(jq -r '[.hooks.SessionStart[] | select(.matcher == "compact") | .hooks[].command
               | select(test("hooks/prose-session-start[.]sh"))] | length' "$cfg")" 1
  eq "the registered script exists" "$([ -f "$script" ] && echo yes || echo no)" yes
}

names_cases() {
  local conv
  conv=$(dirname "$(dirname "$script")")/conventions/reuse.md
  eq "reuse.md L3 manifest list matches the script" \
    "$(grep '^- L3 ' "$conv" | sed -n 's/.*touched package (\([^)]*\)).*/\1/p' | tr -d ' ' | tr ',' '\n' | sort | tr '\n' ' ')" \
    "$(bash "$script" names | sort | tr '\n' ' ')"
}

# One parser run reads every changed file of a type, so state must not leak from one file into the next, and
# one bad file must not cost the other files their entries.
batch_cases() {
  ctx_init
  put a/BUILD.bazel <<'EOF'
java_library(name = "a", deps = [
    "@maven//:a",
EOF
  put b/BUILD.bazel <<'EOF'
java_library(name = "b")
x = ["@maven//:not_a_dep"]
EOF
  put a/Cargo.toml <<'EOF'
[dependencies.serde]
version = "1.0"
EOF
  put b/Cargo.toml <<'EOF'
[package]
name = "b"
EOF
  put good/package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  put bad/package.json <<'EOF'
{not json
EOF
  put -x/BUILD <<'EOF'
cc_library(name = "x", deps = ["@abseil//:strings"])
EOF
  put requirements.txt <<'EOF'
M==1.0
requests==2
EOF
  put c/Cargo.toml <<'EOF'
[dependencies]
python = "0.1"
EOF
  put pom.xml <<'EOF'
<project>
  <dependencyManagement>
    <dependencies>
      <dependency><groupId>g</groupId><artifactId>managed-only</artifactId><version>1</version></dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency><groupId>g</groupId><artifactId>used</artifactId><version>2</version></dependency>
  </dependencies>
  <build><plugins><plugin>
    <artifactId>p</artifactId>
    <dependencies><dependency><groupId>p</groupId><artifactId>plugin-dep</artifactId></dependency></dependencies>
  </plugin></plugins></build>
</project>
EOF
  idx build
  eq "batch: an open BUILD list ends with its file" "$(deps_of b/BUILD.bazel)" "false "
  eq "batch: the open BUILD list keeps its own deps" "$(deps_of a/BUILD.bazel)" "false @maven//:a=null"
  eq "batch: a Cargo dependency is flushed into its own file" "$(deps_of a/Cargo.toml)" "false serde=1.0"
  eq "batch: the next Cargo file gets none of it" "$(deps_of b/Cargo.toml)" "false "
  eq "batch: an invalid package.json is marked" "$(deps_of bad/package.json)" "true "
  eq "batch: the valid package.json keeps its deps" "$(deps_of good/package.json)" "false a=1"
  eq "batch: a path that starts with - is parsed" "$(deps_of -x/BUILD)" "false @abseil//:strings=null"
  eq "batch: a dependency named M stays a dependency" "$(deps_of requirements.txt)" "false M===1.0,requests===2"
  eq "Cargo: a dependency named python is kept" "$(deps_of c/Cargo.toml)" "false python=0.1"
  eq "pom.xml: managed and plugin dependencies are skipped" "$(deps_of pom.xml)" "false g:used=2"
  eq "batch: no stray manifest keys" "$(jq -r '.manifests | keys | map(select(startswith("=") or . == "")) | length' "$repo/.bf/cache/deps.json")" 0
}

names_parse_cases() {
  local name file
  ctx_init
  for name in $(bash "$script" names); do
    file=${name//\*/}
    printf '{}\n' > "$repo/$file"
    git -C "$repo" add "$file"
  done
  idx build
  for name in $(bash "$script" names); do
    file=${name//\*/}
    eq "names: $file has a parser" "$(jq -r --arg f "$file" '.manifests[$f].error' "$repo/.bf/cache/deps.json")" false
  done
}

# hook_command: the deps-index command string from hooks.json with the plugin root filled in.
hook_command() {
  local cfg=$(dirname "$script")/hooks.json
  jq -r '.hooks.SessionStart[] | select(.matcher == "startup|resume|clear") | .hooks[0].command' "$cfg" \
    | sed "s|\${CLAUDE_PLUGIN_ROOT}|$(dirname "$(dirname "$script")")|"
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
  case $1 in */*) mkdir -p "$repo/${1%/*}" ;; esac
  cat > "$repo/$1"
  git -C "$repo" add -- "$1"
}

idx() { (cd "$repo" && bash "$script" "$@"); }

# deps_of <manifest>: "<error> name=version,..." for one index entry, or "missing".
deps_of() {
  jq -r --arg m "$1" '.manifests[$m] | if . == null then "missing"
    else (.error | tostring) + " " + (.deps | map(.name + "=" + (.version // "null")) | join(",")) end' \
    "$repo/.bf/cache/deps.json" 2>/dev/null
}

eq() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails + 1)); fi
}

main "$@"
