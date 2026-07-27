#!/usr/bin/env bash
# Resolve the ADR directory and next ADR number for the current repo.
# Output: single-line JSON — {"adr_dir":"docs/adr","dir_exists":true,"next_number":"0007"}
set -euo pipefail

project_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo '{"error":"not_a_git_repo"}'
  exit 1
}
cd "$project_root"

candidates=(docs/adr docs/decisions docs/architecture/decisions adr)

adr_dir=""
for c in "${candidates[@]}"; do
  if [ -d "$c" ] && find "$c" -maxdepth 1 -name '[0-9]*.md' -print -quit | grep -q .; then
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

last_num=$(find "$adr_dir" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-*.md' 2>/dev/null \
  | sed -E 's#.*/([0-9]{4})-.*#\1#' \
  | sort -n \
  | tail -1) || true

if [ -z "$last_num" ]; then
  next_number="0001"
else
  next_number=$(printf '%04d' "$((10#$last_num + 1))")
fi

printf '{"adr_dir":"%s","dir_exists":%s,"next_number":"%s"}\n' "$adr_dir" "$dir_exists" "$next_number"
