---
name: review
description: Review code (current branch diff, a PR by number, or specific files) against bfeature code-review conventions and the complexity gate.
model: opus
disable-model-invocation: false
argument-hint: "[empty | PR number | file paths]"
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(gh *), Bash(mkdir *), Bash(ln *), Bash(date *), Bash(sha1sum *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first — it contains plugin-wide rules that apply to this skill, including the **one-question-per-turn** rule that applies at every interactive point in this skill.

## On Invocation

### Detect scope from `$ARGUMENTS`

```
if [ -z "$ARGUMENTS" ]; then
  scope=branch
elif echo "$ARGUMENTS" | grep -qE '^\s*[0-9]+\s*$'; then
  scope=pr
  pr_number=$(echo "$ARGUMENTS" | tr -d ' ')
else
  scope=files
  file_paths="$ARGUMENTS"
fi
```

### Verify git repo

Run: `git rev-parse --show-toplevel`

If this fails, print: "Not a git repository. Exiting." and stop.

Set `project_root` to the output.

### Compute project_id and report paths

Derive project_id from the git remote URL (same derivation used in `~/.vs/` artifacts elsewhere):

```bash
PROJECT_ID=$(git config --get remote.origin.url 2>/dev/null \
  | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#; s#/#-#g')
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$project_root")
```

Set paths:

```bash
timestamp=$(date -u +%Y%m%dT%H%M%S)
reports_dir="$HOME/.vs/$PROJECT_ID/reviews"
scope_label=<branch | pr-<pr_number> | files>
report_path="$reports_dir/${timestamp}-${scope_label}-review.md"
complexity_report_path="$reports_dir/${timestamp}-${scope_label}-complexity.md"
```

Create the reports directory: `mkdir -p "$reports_dir"`

### Print banner

```
── bf:review | <Scope> ───────────────────────────────
```

Where `<Scope>` is one of: `Branch`, `PR #<n>`, or `Files: <list>`.

Print as plain text, not in a code block.