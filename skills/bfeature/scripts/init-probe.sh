#!/usr/bin/env bash
# init-probe.sh — Parse invocation arguments and probe git state.
# Replaces manual --quick/GH-ISSUE/Jira detection and git branch probing in the orchestrator.
# Usage: bash init-probe.sh "$ARGUMENTS"
# Outputs JSON.

set -euo pipefail

python3 - "$*" << 'EOF'
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
    'project_root':   root,
}, indent=2))
EOF
