#!/usr/bin/env bash
# Probe a target directory for a new kit, or scaffold the kit into it.
#
# Usage:
#   bash kit-scaffold.sh probe  --dir <target> [--name <kebab-name>]
#   bash kit-scaffold.sh create --dir <target> --name <kebab-name> --description "<one line>"
#
# probe  -> {"target":..,"exists":..,"nonempty":..,"inside_repo":..,"repo_root":..,"git_identity":..,"name_taken":..}
# create -> {"kit_dir":..,"name":..,"files":[..]}  (git init only; the first commit happens after drafting)
set -euo pipefail

MODE="${1-}"
[ $# -gt 0 ] && shift
DIR="" NAME="" DESC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2-}"; shift 2 ;;
    --name) NAME="${2-}"; shift 2 ;;
    --description) DESC="${2-}"; shift 2 ;;
    *) echo "{\"error\":\"unknown_arg\",\"detail\":\"$1\"}"; exit 2 ;;
  esac
done
[ -n "$DIR" ] || { echo '{"error":"no_dir","detail":"pass --dir <target>"}'; exit 1; }

TEMPLATES="$(cd "$(dirname "$0")/../templates" && pwd)"

MODE="$MODE" DIR="$DIR" NAME="$NAME" DESC="$DESC" TEMPLATES="$TEMPLATES" python3 - <<'PY'
import json, os, re, subprocess, sys

mode, templates = os.environ["MODE"], os.environ["TEMPLATES"]
target = os.path.abspath(os.path.expanduser(os.environ["DIR"]))

def git(*args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

def nearest_existing(path):
    while not os.path.exists(path):
        path = os.path.dirname(path)
    return path

def probe():
    exists = os.path.exists(target)
    nonempty = exists and bool(os.listdir(target))
    # A kit created inside another repo would show up there as an embedded repository.
    repo_root = git("rev-parse", "--show-toplevel", cwd=nearest_existing(target))
    identity = bool(git("config", "user.name")) and bool(git("config", "user.email"))
    return {"target": target, "exists": exists, "nonempty": nonempty,
            "inside_repo": repo_root is not None and repo_root != target,
            "repo_root": repo_root, "git_identity": identity,
            "name_taken": installed_plugin(os.environ["NAME"])}

def installed_plugin(name):
    # null when the name is unset or the claude CLI can't answer, so the caller can tell "free" from "unknown".
    if not name:
        return None
    try:
        r = subprocess.run(["claude", "plugin", "list", "--json"], capture_output=True, text=True, timeout=30)
        plugins = json.loads(r.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return any(p.get("id", "").split("@")[0] == name for p in plugins)

def create():
    name, desc = os.environ["NAME"], os.environ["DESC"].strip()
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name):
        return {"error": "bad_name", "detail": "name must be kebab-case: lowercase letters, digits, hyphens"}
    if not desc:
        return {"error": "no_description", "detail": "pass --description \"<one line>\""}
    if os.path.exists(target) and os.listdir(target):
        return {"error": "target_nonempty", "detail": target}

    subs = {"{{KIT_NAME}}": name, "{{KIT_DESCRIPTION}}": desc, "{{KIT_SOURCE_DIR}}": target}
    def render(text):
        for k, v in subs.items():
            text = text.replace(k, v)
        return text

    layout = {"context-main.md": "context/main.md", "README.md": "README.md",
              "BACKLOG.md": "BACKLOG.md", "knowledge-index.md": "knowledge/index.md",
              "skill-skeleton.md": "templates/skill-skeleton.md"}
    skills_dir = os.path.join(templates, "skills")
    for skill in sorted(os.listdir(skills_dir)):
        if os.path.isfile(os.path.join(skills_dir, skill, "SKILL.md")):
            layout[f"skills/{skill}/SKILL.md"] = f"skills/{skill}/SKILL.md"

    written = []
    def write(rel, content):
        path = os.path.join(target, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
        written.append(rel)

    for src, dst in layout.items():
        with open(os.path.join(templates, src)) as f:
            write(dst, render(f.read()))

    author = {"name": git("config", "user.name") or "local"}
    write(".claude-plugin/plugin.json", json.dumps(
        {"name": name, "description": desc, "version": "0.1.0", "author": author}, indent=2) + "\n")
    write(".claude-plugin/marketplace.json", json.dumps(
        {"name": f"{name}-local", "description": f"Local marketplace for the {name} kit.",
         "owner": author, "plugins": [{"name": name, "description": desc, "source": "."}]},
        indent=2) + "\n")
    write(".gitignore", ".DS_Store\n.bf/\n")

    if git("init", "-q", "-b", "main", cwd=target) is None:
        return {"error": "git_init_failed", "detail": target, "files": written}
    return {"kit_dir": target, "name": name, "files": written}

result = probe() if mode == "probe" else create() if mode == "create" else \
    {"error": "bad_mode", "detail": "first argument must be probe or create"}
print(json.dumps(result))
sys.exit(1 if "error" in result else 0)
PY
