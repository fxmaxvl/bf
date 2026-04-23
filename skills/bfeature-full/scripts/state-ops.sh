#!/usr/bin/env bash
# state-ops.sh — Read, update, or initialize build-state.json.
#
# Usage:
#   bash state-ops.sh                          # read: output state + computed artifact paths as JSON
#   bash state-ops.sh key=value [key2=value2]  # update: set fields, auto-bumps updated_at
#   bash state-ops.sh --init --slug <slug> --idea <idea> \
#                     [--mode quick|full] \
#                     [--jira-key PROJ-123 --jira-url <url>] \
#                     [--gh-issue 42]          # init: create build-state.json, output paths JSON
#
# Update supports dot notation for nested fields:
#   phase=execute
#   phase_status=in_progress
#   artifacts.plan=20260409T14-dark-mode-plan.md
#   collect_todos=true
#   jira.enabled=true
#
# Boolean values (true/false) and null are written as JSON primitives, not strings.

set -euo pipefail

python3 - "$@" << 'EOF'
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

def git_root():
    r = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    if r.returncode != 0:
        print("Error: not inside a git repository", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()

def set_nested(obj, dotted_key, value):
    keys = dotted_key.split('.')
    for key in keys[:-1]:
        if key not in obj or not isinstance(obj[key], dict):
            obj[key] = {}
        obj = obj[key]
    obj[keys[-1]] = value

def parse_value(raw):
    if raw == 'true':  return True
    if raw == 'false': return False
    if raw == 'null':  return None
    return raw

def artifact_paths(adir, prefix):
    def p(name):
        return os.path.join(adir, f'{prefix}-{name}.md')
    return {
        'spec':          p('spec'),
        'qa':            p('qa'),
        'plan':          p('plan'),
        'todo':          p('todo'),
        'design_report': p('design-report'),
        'impl_report':   p('impl-report'),
        'backlog':       p('backlog'),
        'deployment':    p('deployment'),
    }

def read_output(root, state):
    slug  = state['slug']
    ts    = state['build_timestamp']
    adir  = os.path.join(root, '.claude', '.bfeature-temp')
    prefix = f'{ts}-{slug}'
    print(json.dumps({
        'slug':            slug,
        'build_timestamp': ts,
        'mode':            state['mode'],
        'phase':           state['phase'],
        'phase_status':    state['phase_status'],
        'artifacts_dir':   adir,
        'artifact_prefix': prefix,
        'paths':           artifact_paths(adir, prefix),
        'github_issue':    state.get('github_issue', {}),
        'jira':            state.get('jira', {}),
    }, indent=2))

root = git_root()
state_path = os.path.join(root, '.claude', '.bfeature-temp', 'build-state.json')
args = sys.argv[1:]

# ── Init mode ──────────────────────────────────────────────────────────────
if args and args[0] == '--init':
    params = {}
    i = 1
    while i < len(args):
        key = args[i]
        if key in ('--slug', '--idea', '--mode', '--jira-key', '--jira-url', '--gh-issue'):
            if i + 1 >= len(args):
                print(f"Error: {key} requires a value", file=sys.stderr)
                sys.exit(1)
            params[key.lstrip('-').replace('-', '_')] = args[i + 1]
            i += 2
        else:
            print(f"Error: unknown --init argument '{key}'", file=sys.stderr)
            sys.exit(1)

    for required in ('slug', 'idea'):
        if required not in params:
            print(f"Error: --{required} is required for --init", file=sys.stderr)
            sys.exit(1)

    if os.path.exists(state_path):
        print(f"Error: build-state.json already exists at {state_path}. Delete it or resume the existing run.", file=sys.stderr)
        sys.exit(1)

    slug     = params['slug']
    idea     = params['idea']
    mode     = params.get('mode', 'full')
    now      = datetime.now(timezone.utc)
    ts       = now.strftime('%Y%m%dT%H')
    iso_now  = now.isoformat()
    jira_key = params.get('jira_key')
    jira_url = params.get('jira_url')
    gh_issue = params.get('gh_issue')

    adir = os.path.join(root, '.claude', '.bfeature-temp')
    os.makedirs(adir, exist_ok=True)

    state = {
        'idea': idea,
        'slug': slug,
        'build_timestamp': ts,
        'mode': mode,
        'phase': 'refine' if mode == 'quick' else 'brainstorm',
        'phase_status': 'in_progress',
        'github_issue': {
            'enabled': gh_issue is not None,
            'number': int(gh_issue) if gh_issue else None,
        },
        'jira': {
            'enabled': jira_key is not None,
            'ticket_key': jira_key,
            'ticket_url': jira_url,
            'pending_questions': None,
        },
        'collect_todos': None,
        'artifacts': {'spec': None, 'plan': None, 'todo': None, 'backlog': None},
        'created_at': iso_now,
        'updated_at': iso_now,
    }

    with open(state_path, 'w') as f:
        json.dump(state, f, indent=2)

    prefix = f'{ts}-{slug}'
    print(json.dumps({
        'slug':            slug,
        'build_timestamp': ts,
        'mode':            mode,
        'phase':           state['phase'],
        'artifacts_dir':   adir,
        'artifact_prefix': prefix,
        'paths':           artifact_paths(adir, prefix),
        'github_issue':    state['github_issue'],
        'jira':            state['jira'],
    }, indent=2))

# ── Read / Update mode ─────────────────────────────────────────────────────
else:
    if not os.path.exists(state_path):
        print(json.dumps({'error': f'build-state.json not found at {state_path}'}), file=sys.stderr)
        sys.exit(1)

    with open(state_path) as f:
        state = json.load(f)

    if not args:
        # Read mode
        read_output(root, state)
    else:
        # Update mode
        for arg in args:
            if '=' not in arg:
                print(f"Error: invalid argument '{arg}' — expected key=value or --init", file=sys.stderr)
                sys.exit(1)
            key, _, raw = arg.partition('=')
            set_nested(state, key.strip(), parse_value(raw))

        state['updated_at'] = datetime.now(timezone.utc).isoformat()

        with open(state_path, 'w') as f:
            json.dump(state, f, indent=2)

        print(f"Updated: {', '.join(args)}")
EOF
