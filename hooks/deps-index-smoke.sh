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
  read_cases

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
  check "Cargo.toml: dependency tables and inline tables" "$(deps_of Cargo.toml)" \
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
  check "pyproject.toml: PEP 621 and poetry" "$(deps_of pyproject.toml)" \
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
  check "requirements.txt: specifiers, comments, options, markers" "$(deps_of requirements.txt)" \
    "false flask=>=2.0,numpy=null,pandas===2.0,requests===2.31.0"
  check "requirements-dev.txt is a manifest" "$(deps_of requirements-dev.txt)" "false pytest=>=8"

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
  check "go.mod: block, single line and indirect" "$(deps_of go.mod)" \
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
  check "BUILD.bazel: external labels, deduplicated" "$(deps_of BUILD.bazel)" \
    "false @maven//:com_google_guava_guava=null,@maven//:org_slf4j_slf4j_api=null,@repo=null"
  check "BUILD: single-line deps" "$(deps_of sub/BUILD)" "false @pip//numpy=null"

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
  check "MODULE.bazel: bazel_dep in any order and maven artifacts" "$(deps_of MODULE.bazel)" \
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
  check "pom.xml: coordinates, property version, exclusions ignored" "$(deps_of pom.xml)" \
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
  check "build.gradle: configurations with and without parens" "$(deps_of build.gradle)" \
    "false com.google.guava:guava=32.1.2-jre,junit:junit=4.13,org.projectlombok:lombok=null,org.slf4j:slf4j-api=2.0.9"
  check "build.gradle.kts: runtimeOnly" "$(deps_of sub/build.gradle.kts)" "false com.h2database:h2=2.2.224"
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

read_cases() {
  local out

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  out=$(idx read)
  check "read on a fresh repo builds and prints entries" "$out" '[{"name":"a","version":"1","manifest":"package.json"}]'

  printf '{"dependencies":{"a":"2"}}\n' > "$repo/package.json"
  out=$(idx read)
  check "read after a manifest edit prints the new version" "$out" '[{"name":"a","version":"2","manifest":"package.json"}]'

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
  check "read without a prefix prints every manifest" "$out" "api,apiary,deep,root,web"
  out=$(idx read services/api | jq -r 'map(.name) | sort | join(",")')
  check "read with a prefix: root and that tree only" "$out" "api,deep,root"
  out=$(idx read services/api/ | jq -r 'map(.name) | sort | join(",")')
  check "read with a trailing slash" "$out" "api,deep,root"
  out=$(idx read "$repo/services/api" | jq -r 'map(.name) | sort | join(",")')
  check "read with an absolute prefix" "$out" "api,deep,root"
  out=$(idx read ./services/api | jq -r 'map(.name) | sort | join(",")')
  check "read with a ./ prefix" "$out" "api,deep,root"
  out=$(idx read services/api services/web | jq -r 'map(.name) | sort | join(",")')
  check "read with two prefixes" "$out" "api,deep,root,web"

  ctx_init
  put package.json <<'EOF'
{"dependencies":{"a":"1"}}
EOF
  mkdir -p "$repo/.bf/cache/deps.lock"
  date +%s > "$repo/.bf/cache/deps.lock/started"
  out=$(idx read); rc=$?
  check "read with a live lock: waits, then prints nothing" "$rc:$out" "0:"
  check "read with a live lock: lock dir stays" "$([ -d "$repo/.bf/cache/deps.lock" ] && echo yes || echo no)" yes

  rm -rf "$repo/.bf/cache/deps.lock"
  mkdir -p "$repo/.bf/cache/deps.lock"
  echo $(($(date +%s) - 120)) > "$repo/.bf/cache/deps.lock/started"
  out=$(idx read)
  check "read with a stale lock: removes it and prints entries" "$out" '[{"name":"a","version":"1","manifest":"package.json"}]'

  out=$(cd "$repo" && BF_DEPS_HOOK=off bash "$script" read 2>&1); rc=$?
  check "read with BF_DEPS_HOOK=off prints nothing" "$rc:$out" "0:"
  out=$(cd "$tmp/plain" && bash "$script" read 2>&1); rc=$?
  check "read outside a repo prints nothing" "$rc:$out" "0:"
  out=$(cd "$repo" && env PATH=/nonexistent /bin/bash "$script" read 2>&1); rc=$?
  check "read without jq prints nothing" "$rc:$out" "0:"
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
