#!/usr/bin/env bash
# Gate bf skill changes against stored eval scores. Maintainer tooling for this repo only.
#
# Usage: regress.sh --pre-push <remote> <url>        git pre-push hook mode, reads ref lines on stdin
#        regress.sh --coverage [<base>]              free check: every added skill has a tagged case
#        regress.sh --check [<base>]                 coverage, then the regression check at HEAD
#        regress.sh --update-baseline [--tag <t>...] [--force]
#                                                    run cases and write evals/baseline.json
#        regress.sh --compare [<ref>] [--tag <t>...] old-vs-new scores, <ref> defaults to REGRESS_BASE
# Output: findings and tables on stdout, reasons on stderr.
# Exit:   0 pass, 1 blocked or error.
#
# Settings: evals/regress.conf holds KEY=value lines. An environment variable of the same name wins.
# REGRESS_BASE comes from the environment or the default origin/main only. A branch must not
# point its own gate at its own baseline.
#
# Source of each input per mode. The hook and --check read the baseline and the conf from
# REGRESS_BASE, so one push cannot lower its own bar.
#   mode             plugin tree   case definitions   baseline.json   regress.conf
#   pre-push         pushed        pushed             base            base
#   coverage         none          head               none            base
#   check            head          head               base            base
#   update-baseline  head          head               wt              wt
#   compare-old      ref           wt                 none            wt
#   compare-new      wt            wt                 none            wt

CONF_KEYS="REGRESS_MARGIN REGRESS_MODEL REGRESS_JUDGE_MODEL REGRESS_RUNS REGRESS_MAX_COST_USD REGRESS_CONCURRENCY"

# Keys set in the environment at load time, so a conf value never replaces them.
ENV_KEYS=""
for _key in $CONF_KEYS; do
  if [ -n "${!_key+x}" ]; then ENV_KEYS="$ENV_KEYS $_key"; fi
done
unset _key
REGRESS_BASE=${REGRESS_BASE:-origin/main}

die() {
  echo "regress: $*" >&2
  exit 1
}

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

conf_default() {
  case "$1" in
    REGRESS_MARGIN) echo 0.34 ;;
    REGRESS_MODEL) echo claude-sonnet-5-5 ;;
    REGRESS_JUDGE_MODEL) echo claude-haiku-5-5 ;;
    REGRESS_RUNS) echo 3 ;;
    REGRESS_MAX_COST_USD) echo 10 ;;
    REGRESS_CONCURRENCY) echo 4 ;;
  esac
}

repo_root() {
  git rev-parse --show-toplevel </dev/null
}

# Reads a file at a commit, or from the working tree when the source is WT.
read_at() {
  local src=$1 path=$2 root
  if [ "$src" = WT ]; then
    root=$(repo_root) || return 1
    cat "$root/$path" 2>/dev/null
  else
    git show "$src:$path" </dev/null 2>/dev/null
  fi
}

# Load order: built-in default, then the conf file at <src>, then the environment.
conf_load() {
  local src=$1 key val conf
  conf=$(read_at "$src" evals/regress.conf) || conf=""
  for key in $CONF_KEYS; do
    case " $ENV_KEYS " in
      *" $key "*) continue ;;
    esac
    val=$(printf '%s\n' "$conf" | sed -n "s/^$key=//p" | tail -n 1 | sed "s/^[\"']//; s/[\"']\$//")
    printf -v "$key" '%s' "${val:-$(conf_default "$key")}"
  done
}

# The one mode-by-input resolver. It prints a source symbol that src_ref turns into a ref.
src_for() {
  local mode=$1 input=$2
  case "$mode:$input" in
    pre-push:plugin | pre-push:cases) echo pushed ;;
    pre-push:baseline | pre-push:conf) echo base ;;
    coverage:plugin | coverage:baseline) echo none ;;
    coverage:cases) echo head ;;
    coverage:conf) echo base ;;
    check:plugin | check:cases) echo head ;;
    check:baseline | check:conf) echo base ;;
    update-baseline:plugin | update-baseline:cases) echo head ;;
    update-baseline:baseline | update-baseline:conf) echo wt ;;
    compare-old:plugin) echo ref ;;
    compare-old:cases | compare-old:conf) echo wt ;;
    compare-old:baseline) echo none ;;
    compare-new:plugin | compare-new:cases | compare-new:conf) echo wt ;;
    compare-new:baseline) echo none ;;
    *) return 1 ;;
  esac
}

# Turns a source symbol into a ref for read_at. The optional second argument is the pushed sha or the compare ref.
src_ref() {
  case "$1" in
    head) echo HEAD ;;
    base) echo "$REGRESS_BASE" ;;
    wt) echo WT ;;
    pushed | ref) echo "${2:-}" ;;
    none) echo "" ;;
    *) return 1 ;;
  esac
}

# Prints the values of one top-level key from YAML text on stdin, one per line. It reads the flow
# form (key: [a, b]) and the block form (- a lines). Any other value exits 3.
yaml_list() {
  awk -v key="$1" -v q="'" '
    function clean(x) {
      gsub(/^[ \t"]+|[ \t"]+$/, "", x)
      gsub("^" q "|" q "$", "", x)
      return x
    }
    function emit(x) {
      x = clean(x)
      if (x ~ /[{}\[\]]/ || x ~ /:[ \t]/) { bad = 1 } else if (x != "") { print x }
    }
    $0 ~ "^" key ":" {
      v = $0
      sub("^" key ":[ \t]*", "", v)
      sub(/[ \t]+#.*$/, "", v)
      sub(/[ \t]+$/, "", v)
      inblock = 0
      if (v ~ /^\[.*\]$/) {
        sub(/^\[/, "", v); sub(/\]$/, "", v)
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) emit(parts[i])
      } else if (v == "") {
        inblock = 1
      } else {
        bad = 1
      }
      next
    }
    inblock && /^[ \t]*-[ \t]+/ { x = $0; sub(/^[ \t]*-[ \t]+/, "", x); emit(x); next }
    inblock && /^[ \t]*$/ { next }
    inblock && /^[ \t]/ { bad = 1; next }
    { inblock = 0 }
    END { if (bad) exit 3 }
  '
}

# Prints the lines between the first two --- lines when the text on stdin starts with ---.
frontmatter() {
  awk 'NR == 1 { if ($0 != "---") exit; next } /^---[ \t]*$/ { exit } { print }'
}

# Lists the case dirs under evals/ that hold a case.yaml or a prompt.md. results/ is never a case.
list_cases() {
  local src=$1 root
  if [ "$src" = WT ]; then
    root=$(repo_root) || return 1
    (cd "$root" && find evals -mindepth 2 -maxdepth 2 \( -name case.yaml -o -name prompt.md \) -print </dev/null)
  else
    git ls-tree -r --name-only "$src" -- evals </dev/null
  fi | sed -En 's#^evals/([^/]+)/(case.yaml|prompt.md)$#\1#p' | grep -v '^results$' | sort -u || true
  return 0
}

# Prints the values of a key (tags or allowed_tools) from both case files, joined with no
# duplicates. A key that is present but unreadable stops the run and names the file.
case_meta() {
  local src=$1 case=$2 key=$3 file text part all=""
  for file in case.yaml prompt.md; do
    text=$(read_at "$src" "evals/$case/$file") || continue
    if [ "$file" = prompt.md ]; then text=$(printf '%s\n' "$text" | frontmatter); fi
    part=$(printf '%s\n' "$text" | yaml_list "$key") || {
      echo "regress: cannot read the $key key in evals/$case/$file" >&2
      return 1
    }
    all=$all$part$'\n'
  done
  printf '%s' "$all" | awk 'NF && !seen[$0]++'
  return 0
}

cases_with_tag() {
  local src=$1 tag=$2 case tags
  while IFS= read -r case; do
    tags=$(case_meta "$src" "$case" tags) || return 1
    if printf '%s\n' "$tags" | grep -qxF -- "$tag"; then echo "$case"; fi
  done < <(list_cases "$src")
  return 0
}

# The git tree id of a case dir at a commit. It is empty when the dir is absent there.
case_tree() {
  git rev-parse --verify -q "$1:evals/$2" </dev/null || true
}

# Maps a diff to skill names. Output lines are "added <name>" or "edited <name>". A skill is a
# top-level dir of skills/ with a SKILL.md at the head. The head is a commit or WT, and WT also
# counts untracked files.
changed_skills() {
  local base=$1 head=$2 root names name kind
  root=$(repo_root) || return 1
  if [ "$head" = WT ]; then
    names=$({ git diff --name-only --no-renames "$base" -- skills </dev/null
      git ls-files --others --exclude-standard -- skills </dev/null; }) || return 1
  else
    names=$(git diff --name-only --no-renames "$base" "$head" -- skills </dev/null) || return 1
  fi
  names=$(printf '%s\n' "$names" | sed -En 's#^skills/([^/]+)/.+#\1#p' | sort -u)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$head" = WT ]; then
      [ -f "$root/skills/$name/SKILL.md" ] || continue
    else
      git cat-file -e "$head:skills/$name/SKILL.md" </dev/null 2>/dev/null || continue
    fi
    kind=edited
    git cat-file -e "$base:skills/$name/SKILL.md" </dev/null 2>/dev/null || kind=added
    echo "$kind $name"
  done <<<"$names"
  return 0
}

main() {
  set -euo pipefail
  command -v jq >/dev/null 2>&1 || die "jq is required. Install it and run again."
  case "${1:-}" in
    *) usage; exit 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
