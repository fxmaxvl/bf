#!/usr/bin/env bash
# changed-packages.sh — List files changed since the base branch and resolve affected monorepo packages.
# Outputs JSON.
# Usage: bash changed-packages.sh [--base <branch>]
#   --base   Branch to diff against (default: master)

set -euo pipefail

BASE="master"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

python3 - "$BASE" << 'EOF'
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
    affected = set()
    for f in files:
        for ws in workspaces:
            # Strip glob wildcards for prefix matching (e.g. "packages/*" → "packages/")
            prefix = ws.rstrip('*').rstrip('/')
            if f.startswith(prefix + '/') or f == prefix:
                # Use the actual directory, not the glob pattern
                parts = f.split('/')
                ws_parts = prefix.split('/')
                pkg_dir = '/'.join(parts[:len(ws_parts) + 1])
                affected.add(pkg_dir)
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
