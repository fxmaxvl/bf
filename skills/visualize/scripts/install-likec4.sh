#!/usr/bin/env bash
# Install the pinned likec4 once into a versioned cache and prove the binary runs.
#
# Usage:  install-likec4.sh [--print-version]
# Output: {"bin":...,"version":...,"cache_dir":...,"allowlist":[<Perl regex>...]}
#         --print-version prints LIKEC4_VERSION and exits without installing.
#         Cache root is $BF_LIKEC4_CACHE_DIR, default $HOME/.bf/cache (test seam).
# Errors: {"error":...,"detail":...} + exit 1 — no_node, mirror_lag, install_failed, verify_failed, jq_missing.

# Version bump checklist: bump here -> re-capture the allowlist below from a clean build -> re-run visualize-smoke.sh.
LIKEC4_VERSION=1.59.3
# Bare (non-timestamped) vite lines of a clean build; classify-output.sh fails every other bare line.
LIKEC4_ALLOWLIST='^transforming\.\.\.$
^.+ [0-9,]+ modules transformed\.$
^rendering chunks\.\.\.$
^computing gzip size\.\.\.$
^.+/index\.html +[0-9,.]+ kB .+ gzip: +[0-9,.]+ kB$'

set -euo pipefail

if [ "${1:-}" = "--print-version" ]; then echo "$LIKEC4_VERSION"; exit 0; fi

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
fail() { jq -cn --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'; exit 1; }

command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || fail no_node "node and npm are required to build the diagram; install Node.js and re-run"

cache_dir=${BF_LIKEC4_CACHE_DIR:-$HOME/.bf/cache}/likec4@$LIKEC4_VERSION
bin=$cache_dir/node_modules/.bin/likec4

runs_pinned() { [ -x "$bin" ] && "$bin" --version 2>&1 | grep -qF "$LIKEC4_VERSION"; }

install_pinned() {
  local out
  rm -rf "$cache_dir"; mkdir -p "$cache_dir"
  if ! out=$(npm install --prefix "$cache_dir" --no-save --no-audit --no-fund "likec4@$LIKEC4_VERSION" 2>&1); then
    rm -rf "$cache_dir"
    if printf '%s' "$out" | grep -Eq 'ETARGET|E404|404 Not Found'; then
      fail mirror_lag "the npm registry or mirror has not synced likec4@$LIKEC4_VERSION. The version is pinned on purpose, so no other version is tried. Retry later, or point npm at the public registry: npm_config_registry=https://registry.npmjs.org/"
    fi
    fail install_failed "npm install likec4@$LIKEC4_VERSION failed: $(printf '%s' "$out" | tail -n 5 | tr '\n' ' ')"
  fi
}

if ! runs_pinned; then
  install_pinned
  runs_pinned || { rm -rf "$cache_dir"; fail verify_failed "likec4 installed under $cache_dir but does not report $LIKEC4_VERSION"; }
fi

jq -cn --arg bin "$bin" --arg v "$LIKEC4_VERSION" --arg dir "$cache_dir" --arg al "$LIKEC4_ALLOWLIST" \
  '{bin:$bin, version:$v, cache_dir:$dir, allowlist:($al | split("\n") | map(select(. != "")))}'
