#!/usr/bin/env bash
# List the subsystems directly contained at a path, for one round of the layered descent.
# A subsystem is a build/deploy unit; where a path contains none, immediate subdirectories are
# the fallback. Nearest-enclosing marker wins: a directory whose closest marker above it belongs
# to an already-accepted unit is part of that unit, not a sibling of it — without this rule a
# repo with markers at several depths yields a different tree on every run.
# Usage:  detect-units.sh <path>
# Output: single-line JSON —
#   {"path":"services","mode":"build","has_children":true,
#    "units":[{"name":"payments","path":"services/payments","marker":"BUILD.bazel"}]}
set -euo pipefail

target="${1:-.}"
[ -d "$target" ] || { printf '{"error":"not_a_directory","path":"%s"}\n' "$target"; exit 1; }

markers='BUILD.bazel BUILD package.json go.mod Cargo.toml pom.xml build.gradle build.gradle.kts pyproject.toml setup.py Dockerfile'
prune_names='.git node_modules vendor target dist build .venv __pycache__ .bf bazel-bin bazel-out .idea .gradle'

prune_expr=()
for p in $prune_names; do prune_expr+=( -name "$p" -o ); done
unset 'prune_expr[${#prune_expr[@]}-1]'

name_expr=()
for m in $markers; do name_expr+=( -name "$m" -o ); done
name_expr+=( -name '*.csproj' )

found=$(find "$target" \( "${prune_expr[@]}" \) -prune -o -type f \( "${name_expr[@]}" \) -print 2>/dev/null | sort) || true

declare -a accepted_paths=() accepted_markers=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  d=$(dirname "$f")
  [ "$d" = "$target" ] && continue          # the marker of the unit being descended into, not a child
  skip=false
  for a in "${accepted_paths[@]:-}"; do
    [ -n "$a" ] && case "$d/" in "$a"/*) skip=true; break;; esac
  done
  $skip && continue
  for a in "${accepted_paths[@]:-}"; do [ "$a" = "$d" ] && skip=true && break; done
  $skip && continue
  accepted_paths+=("$d")
  accepted_markers+=("$(basename "$f")")
done <<< "$(printf '%s\n' "$found" | awk '{print gsub(/\//,"/")"\t"$0}' | sort -n | cut -f2-)"

mode=build
if [ ${#accepted_paths[@]} -eq 0 ]; then
  mode=dir
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    accepted_paths+=("$d"); accepted_markers+=("")
  done <<< "$(find "$target" -mindepth 1 -maxdepth 1 -type d ! -name '.*' \( "${prune_expr[@]}" \) -prune -o -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print 2>/dev/null | sort)"
fi

entries=()
for i in "${!accepted_paths[@]}"; do
  pth="${accepted_paths[$i]}"
  [ -z "$pth" ] && continue
  entries+=("{\"name\":\"$(basename "$pth")\",\"path\":\"${pth#./}\",\"marker\":\"${accepted_markers[$i]}\"}")
done

units_json="[]"
if [ ${#entries[@]} -gt 0 ]; then
  joined=$(printf '%s,' "${entries[@]}")
  units_json="[${joined%,}]"
fi

has_children=false
[ ${#entries[@]} -gt 0 ] && has_children=true

printf '{"path":"%s","mode":"%s","has_children":%s,"units":%s}\n' "${target#./}" "$mode" "$has_children" "$units_json"
