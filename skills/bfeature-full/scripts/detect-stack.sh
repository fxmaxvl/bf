#!/usr/bin/env bash
# detect-stack.sh — Detect project tech stack and quality-gate commands.
# Outputs JSON. Run from anywhere in the project — resolves git root automatically.
# Usage: bash detect-stack.sh

set -euo pipefail

python3 - << 'EOF'
import json
import os
import subprocess
import sys

def git_root():
    r = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    if r.returncode != 0:
        print("Error: not inside a git repository", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()

def cmd_exists(cmd):
    return subprocess.run(['which', cmd], capture_output=True).returncode == 0

def detect(root):
    os.chdir(root)

    out = {
        'type': 'unknown',
        'package_manager': None,
        'test_commands': [],
        'lint_command': None,
        'lint_fix_command': None,
        'monorepo': False,
        'monorepo_type': None,
        'workspaces': [],
        'scope_template': None,
    }

    if os.path.exists('go.mod'):
        out['type'] = 'go'
        out['test_commands'] = ['go test ./...']
        if cmd_exists('golangci-lint'):
            out['lint_command'] = 'golangci-lint run'
            out['lint_fix_command'] = 'golangci-lint run --fix'
        else:
            out['lint_command'] = 'gofmt -l .'
            out['lint_fix_command'] = 'gofmt -w .'
        if os.path.exists('go.work'):
            out['monorepo'] = True
            out['monorepo_type'] = 'go-work'
            out['scope_template'] = 'go test {{package}}/...'
            dirs = []
            with open('go.work') as f:
                in_block = False
                for line in f:
                    line = line.strip()
                    if line.startswith('use ('):
                        in_block = True
                    elif line == ')':
                        in_block = False
                    elif in_block and line:
                        dirs.append(line)
                    elif line.startswith('use ') and not line.startswith('use ('):
                        parts = line.split()
                        if len(parts) >= 2:
                            dirs.append(parts[1])
            out['workspaces'] = dirs

    elif os.path.exists('Cargo.toml'):
        out['type'] = 'rust'
        out['test_commands'] = ['cargo test']
        out['lint_command'] = 'cargo clippy'
        out['lint_fix_command'] = 'cargo clippy --fix --allow-dirty'

    elif os.path.exists('pom.xml'):
        out['type'] = 'java'
        out['test_commands'] = ['mvn test']

    elif os.path.exists('build.gradle') or os.path.exists('build.gradle.kts'):
        out['type'] = 'java'
        out['test_commands'] = ['./gradlew test']

    elif os.path.exists('pyproject.toml') or os.path.exists('setup.py'):
        out['type'] = 'python'
        out['test_commands'] = ['pytest']
        if cmd_exists('ruff'):
            out['lint_command'] = 'ruff check .'
            out['lint_fix_command'] = 'ruff check --fix .'
        elif cmd_exists('flake8'):
            out['lint_command'] = 'flake8 .'

    elif os.path.exists('package.json'):
        out['type'] = 'node'

        with open('package.json') as f:
            pkg = json.load(f)
        scripts = list((pkg.get('scripts') or {}).keys())

        # Package manager
        if os.path.exists('pnpm-lock.yaml'):
            pm = 'pnpm'
        elif os.path.exists('yarn.lock'):
            pm = 'yarn'
        else:
            pm = 'npm'
        out['package_manager'] = pm

        # Test commands
        for s in ['test', 'test:unit', 'test:integration', 'test:e2e']:
            if s in scripts:
                out['test_commands'].append(f'{pm} run {s}')

        # Lint
        for s in ['lint', 'eslint']:
            if s in scripts:
                out['lint_command'] = f'{pm} run {s}'
                break
        for s in ['lint:fix', 'eslint:fix', 'format:fix', 'format']:
            if s in scripts:
                out['lint_fix_command'] = f'{pm} run {s}'
                break

        # Monorepo detection — checked in priority order
        if os.path.exists('pnpm-workspace.yaml'):
            out['monorepo'] = True
            out['monorepo_type'] = 'pnpm-workspaces'
            out['scope_template'] = 'pnpm --filter {{package}} run {{command}}'
            try:
                import yaml
                with open('pnpm-workspace.yaml') as f:
                    ws = yaml.safe_load(f)
                out['workspaces'] = ws.get('packages', [])
            except ImportError:
                # yaml not available — fallback to filesystem scan
                pkgs = []
                for dirpath, dirnames, filenames in os.walk('.'):
                    dirnames[:] = [d for d in dirnames
                                   if d not in ('node_modules', '.git', '.claude')]
                    if dirpath != '.' and 'package.json' in filenames:
                        pkgs.append(os.path.relpath(dirpath, '.'))
                out['workspaces'] = pkgs
        else:
            ws = pkg.get('workspaces', [])
            if isinstance(ws, dict):
                ws = ws.get('packages', [])
            if ws:
                out['monorepo'] = True
                out['monorepo_type'] = 'npm-workspaces'
                out['scope_template'] = f'{pm} run {{{{command}}}} --workspace={{{{package}}}}'
                out['workspaces'] = ws
            elif os.path.exists('lerna.json'):
                with open('lerna.json') as f:
                    lerna = json.load(f)
                out['monorepo'] = True
                out['monorepo_type'] = 'lerna'
                out['workspaces'] = lerna.get('packages', [])

    return out

print(json.dumps(detect(git_root()), indent=2))
EOF
