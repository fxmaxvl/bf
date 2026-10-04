#!/usr/bin/env bash
# Enumerate user-defined convention files from project and user tiers.
# Output: JSON array [{filename, tier, first_heading, path}], or [] if none found.
# Usage: discover-conventions.sh [PROJECT_ROOT]

set -euo pipefail

# shellcheck source=convention-tiers.sh
source "$(dirname "${BASH_SOURCE[0]}")/convention-tiers.sh"

PROJECT_DIR=""
USER_DIR=""
while IFS=$'\t' read -r tier dir; do
  case "$tier" in
    project) PROJECT_DIR="$dir" ;;
    user) USER_DIR="$dir" ;;
  esac
done < <(convention_tiers "${1:-}")

# A newline-delimited list rather than `declare -A`, which macOS /bin/bash 3.2 lacks.
seen=$'\n'
results=()

add_file() {
  local path="$1" tier="$2"
  local filename
  filename="$(basename "$path")"
  [[ "$seen" == *$'\n'"$filename"$'\n'* ]] && return
  seen+="$filename"$'\n'
  local first_heading
  first_heading="$(grep -m1 '^#' "$path" 2>/dev/null || echo "")"
  results+=("{\"filename\":$(printf '%s' "$filename" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))'),\"tier\":\"$tier\",\"first_heading\":$(printf '%s' "$first_heading" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))'),\"path\":$(printf '%s' "$path" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')}")
}

# Project tier wins — process first
if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
  while IFS= read -r -d '' f; do
    add_file "$f" "project"
  done < <(find "$PROJECT_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null | sort -z)
fi

# User tier
if [[ -d "$USER_DIR" ]]; then
  while IFS= read -r -d '' f; do
    add_file "$f" "user"
  done < <(find "$USER_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null | sort -z)
fi

if [[ ${#results[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Join into JSON array
printf '['
for i in "${!results[@]}"; do
  [[ $i -gt 0 ]] && printf ','
  printf '%s' "${results[$i]}"
done
printf ']\n'
