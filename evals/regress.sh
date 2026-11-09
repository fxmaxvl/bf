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
