#!/usr/bin/env bash
# Resolve the ADR directory, next ADR number, and existing ADRs for the current repo.
# Output: single-line JSON —
#   {"adr_dir":"docs/adr","dir_exists":true,"next_number":"0007","adrs":[{"number":"0002","title":"Some Title","path":"docs/adr/0002-some-title.md"}]}
set -euo pipefail

project_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo '{"error":"not_a_git_repo"}'
  exit 1
}
cd "$project_root"

adr_glob="[0-9][0-9][0-9][0-9]-*.md"

candidates=(docs/adr docs/decisions docs/architecture/decisions adr)

adr_dir=""
for c in "${candidates[@]}"; do
  if [ -d "$c" ] && find "$c" -maxdepth 1 -name "$adr_glob" -print -quit | grep -q .; then
    adr_dir="$c"
    break
  fi
done

dir_exists=true
if [ -z "$adr_dir" ]; then
  adr_dir="docs/adr"
  dir_exists=false
  [ -d "$adr_dir" ] && dir_exists=true
fi

last_num=$(find "$adr_dir" -maxdepth 1 -name "$adr_glob" 2>/dev/null \
  | sed -E 's#.*/([0-9]{4})-.*#\1#' \
  | sort -n \
  | tail -1) || true

if [ -z "$last_num" ]; then
  next_number="0001"
else
  next_number=$(printf '%04d' "$((10#$last_num + 1))")
fi

adr_files=$(find "$adr_dir" -maxdepth 1 -name "$adr_glob" 2>/dev/null | sort) || true

adrs_json="[]"
if [ -n "$adr_files" ]; then
  entries=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base=$(basename "$f")
    number="${base:0:4}"
    heading=$(grep -m1 '^# ' "$f" || true)
    title="${heading#\# }"
    title="${title#"$number". }"
    # Escape backslashes first, then quotes — titles are file content and
    # would otherwise produce invalid JSON.
    title="${title//\\/\\\\}"
    title="${title//\"/\\\"}"
    entries+=("{\"number\":\"$number\",\"title\":\"$title\",\"path\":\"$f\"}")
  done <<< "$adr_files"
  joined=$(printf '%s,' "${entries[@]}")
  adrs_json="[${joined%,}]"
fi

printf '{"adr_dir":"%s","dir_exists":%s,"next_number":"%s","adrs":%s}\n' "$adr_dir" "$dir_exists" "$next_number" "$adrs_json"
