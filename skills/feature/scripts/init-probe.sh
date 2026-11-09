#!/usr/bin/env bash
# init-probe.sh — Parse invocation arguments and probe git state.
# Replaces manual --quick/GH-ISSUE/Jira detection and git branch probing in the orchestrator.
# Usage: bash init-probe.sh < <args file>   (the invocation arguments arrive on stdin)
# Outputs JSON.

set -euo pipefail

args=$(cat)

python3 - "$args" << 'EOF'
import json
import os
import re
import subprocess
import sys

args_str = sys.argv[1] if len(sys.argv) > 1 else ""

def git_root():
    r = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    if r.returncode != 0:
        print("Error: not inside a git repository", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()

def current_branch():
    r = subprocess.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else 'HEAD'

def main_branch(root):
    for name in ('main', 'master'):
        r = subprocess.run(
            ['git', 'show-ref', '--verify', f'refs/heads/{name}'],
            capture_output=True, cwd=root
        )
        if r.returncode == 0:
            return name
    r = subprocess.run(
        ['git', 'symbolic-ref', 'refs/remotes/origin/HEAD'],
        capture_output=True, text=True, cwd=root
    )
    if r.returncode == 0:
        return r.stdout.strip().split('/')[-1]
    return 'main'

def parse_args(raw):
    s = raw

    quick = bool(re.search(r'--quick\b', s))
    s = re.sub(r'--quick\b\s*', '', s)

    gh_match = re.search(r'GH-ISSUE:(\d+)', s)
    gh_issue = int(gh_match.group(1)) if gh_match else None
    s = re.sub(r'GH-ISSUE:\d+\s*', '', s)

    jira_match = re.search(
        r'https?://[^\s]+\.atlassian\.net/browse/([A-Z][A-Z0-9]+-\d+)',
        s, re.IGNORECASE
    )
    jira_url = jira_match.group(0) if jira_match else None
    jira_key = jira_match.group(1).upper() if jira_match else None
    if jira_match:
        s = s.replace(jira_match.group(0), '')

    return quick, gh_issue, jira_url, jira_key, s.strip()

quick, gh_issue, jira_url, jira_key, idea = parse_args(args_str)

root = git_root()
cur  = current_branch()
main = main_branch(root)

state_path = os.path.join(root, '.bf', 'sessions', 'build-state.json')

def state_matches():
    """None without state; True when the state belongs to this invocation.

    Empty arguments are a plain resume and always match a feature or quick run. An issue or
    ticket key outranks the idea text, which callers like bf:gh rewrite between runs.
    """
    if not os.path.exists(state_path):
        return None
    try:
        with open(state_path) as f:
            state = json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError, OSError):
        return False
    if not isinstance(state, dict) or not all(
            k in state for k in ('slug', 'build_timestamp', 'phase', 'phase_status')):
        return False
    mode = state.get('mode')
    if mode not in ('full', 'quick'):
        return False
    if not (idea or gh_issue or jira_key):
        return True
    if quick != (mode == 'quick'):
        return False
    if gh_issue or jira_key:
        return (gh_issue == (state.get('github_issue') or {}).get('number')
                and jira_key == (state.get('jira') or {}).get('ticket_key'))
    return idea == (state.get('idea') or '')

print(json.dumps({
    'quick':          quick,
    'gh_issue':       gh_issue,
    'jira_url':       jira_url,
    'jira_key':       jira_key,
    'idea':           idea,
    'current_branch': cur,
    'main_branch':    main,
    'is_main':        cur == main,
    'has_state':      os.path.exists(state_path),
    'state_matches':  state_matches(),
    'project_root':   root,
}, indent=2))
EOF
