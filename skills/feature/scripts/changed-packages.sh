#!/usr/bin/env bash
# changed-packages.sh — List files changed since the base branch and resolve affected monorepo packages.
# Outputs JSON.
# Usage: bash changed-packages.sh [--base <branch>]
#   --base   Branch to diff against (default: resolved from origin/HEAD, then main, then master)

set -euo pipefail

# Resolve default base, preferring remote-tracking refs. A local branch behind its
# remote yields a changed-file list inflated with everything merged upstream since,
# and reports renames as unpaired adds -- silently, since the diff still succeeds.
_resolve_base() {
  local ref b
  ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) && { echo "${ref#refs/remotes/}"; return; }
  for b in origin/main origin/master main master; do
    git rev-parse --verify "$b" >/dev/null 2>&1 && { echo "$b"; return; }
  done
  echo "master"
}
BASE="$(_resolve_base)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

python3 - "$BASE" << 'EOF'
import fnmatch
import json
import os
import subprocess
import sys

base = sys.argv[1]

def git_root():
    r = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    if r.returncode != 0:
        print("Error: not inside a git repository", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()

def changed_files(base, root):
    r = subprocess.run(
        ['git', 'diff', f'{base}...HEAD', '--name-only'],
        capture_output=True, text=True, cwd=root
    )
    if r.returncode != 0:
        return []
    return [f for f in r.stdout.splitlines() if f.strip()]

def get_workspaces(root):
    """Return list of workspace directory prefixes (e.g. ['packages/api', 'apps/web'])."""
    os.chdir(root)
    workspaces = []

    if os.path.exists('go.work'):
        with open('go.work') as f:
            in_block = False
            for line in f:
                line = line.strip()
                if line.startswith('use ('):
                    in_block = True
                elif line == ')':
                    in_block = False
                elif in_block and line:
                    workspaces.append(line)
                elif line.startswith('use ') and not line.startswith('use ('):
                    parts = line.split()
                    if len(parts) >= 2:
                        workspaces.append(parts[1])
        return workspaces

    if not os.path.exists('package.json'):
        return workspaces

    with open('package.json') as f:
        pkg = json.load(f)

    if os.path.exists('pnpm-workspace.yaml'):
        try:
            import yaml
            with open('pnpm-workspace.yaml') as f:
                ws = yaml.safe_load(f)
            return ws.get('packages', [])
        except ImportError:
            pass
        # Fallback: find subdirs with package.json
        for dirpath, dirnames, filenames in os.walk('.'):
            dirnames[:] = [d for d in dirnames
                           if d not in ('node_modules', '.git', '.claude')]
            if dirpath != '.' and 'package.json' in filenames:
                workspaces.append(os.path.relpath(dirpath, '.'))
        return workspaces

    ws = pkg.get('workspaces', [])
    if isinstance(ws, dict):
        ws = ws.get('packages', [])
    if ws:
        return ws

    if os.path.exists('lerna.json'):
        with open('lerna.json') as f:
            lerna = json.load(f)
        return lerna.get('packages', [])

    return workspaces

def resolve_affected(files, workspaces):
    """Map changed files to their workspace package directories."""
    if not workspaces:
        return []
    # Patterns are matched whole, not truncated to their literal prefix: "apps/**/services/*"
    # cannot be reduced to "apps/" without claiming every file under apps/. A leading "!" is
    # pnpm's exclusion — a file under an excluded path belongs to no package.
    # go.work writes its entries as "./api"; changed-file paths never carry the "./".
    def norm(w):
        w = w[2:] if w.startswith('./') else w
        return w.rstrip('/')

    includes = [norm(w) for w in workspaces if not w.startswith('!')]
    excludes = [norm(w[1:]) for w in workspaces if w.startswith('!')]
    affected = set()
    for f in files:
        parts = f.split('/')
        # The shortest matching ancestor is the package root: under "packages/*",
        # "packages/api" matches before "packages/api/src" is ever tried.
        for n in range(1, len(parts)):
            prefix = '/'.join(parts[:n])
            if not any(fnmatch.fnmatch(prefix, p) for p in includes):
                continue
            if not any(fnmatch.fnmatch(prefix, e) for e in excludes):
                affected.add(prefix)
            break
    return sorted(affected)

root = git_root()
files = changed_files(base, root)
workspaces = get_workspaces(root)
affected = resolve_affected(files, workspaces)

print(json.dumps({
    'base': base,
    'changed_files': files,
    'affected_packages': affected,
}, indent=2))
EOF
