---
name: setup
description: Use when setting up bf for the first time, when a bf skill reports a missing tool, or when asked to "install bf dependencies" or "what does bf need". Checks every dependency, lists the install commands, and installs the missing ones after one confirmation.
model: sonnet
disable-model-invocation: true
argument-hint: "[core | status]"
allowed-tools: Bash(bash *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Check and install the tools bf uses. The registry is `skills/setup/deps.json`. The script
`skills/setup/scripts/setup.sh` owns every mechanical step: the checks, the command list and the
installs. This skill prints the results and asks the one question. Every optional tool is opt-in:
bf runs the same without it, and only the skill that needs it reports a gap.

## On Invocation

Print banner (plain text):

```
── bf:setup ─────────────────────────────────────────
```

Map `$ARGUMENTS` to a literal mode. Never put `$ARGUMENTS` itself in a command.

| `$ARGUMENTS` | Mode | Scope word in the commands |
|---|---|---|
| empty | all | `all` |
| `core` | core | `core` |
| `status` | status only | none |
| anything else | status only. Say which mode you ran. | none |

## Phase 1 — Check

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" status
```

Returns `{platform, pkg_manager, deps:[{name, tier, present, detail, features}]}`. Print one table:

| Dep | Tier | Status | Needed by |
|---|---|---|---|

`Status` is `present`, or `missing` plus `detail`. `Needed by` is `features` joined with commas.
The `typesafe` row is a report only: say whether boosting is on, and point to `/bf:typesafe` to
configure it. `/bf:setup` never installs, asks for or prints the key.

In status-only mode, stop here.

## Phase 2 — Plan

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" plan <scope word>
```

| Result | Do |
|---|---|
| `{"blocked":"no_brew","hint":...}` | Print the hint as the line the user runs themselves, then stop. Never run it. |
| `{"error":...}` | Show the error and stop. See Edge Cases. |
| `steps` is empty | Say nothing is missing for this scope, and stop. |
| `steps` has entries | Print every command, numbered in order and grouped under its dep name. If `note` is present, print it below the list. |

## Phase 3 — Confirm

Ask ONE question for the whole batch: "Run these N commands to install the missing dependencies?"
Wait for the answer. On no, stop and say nothing was installed.

## Phase 4 — Install

On yes, run one call per planned dep, in plan order, each with `timeout: 600000` so one slow
install cannot stop the rest:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup.sh" install <scope word> --only <name>
```

Each call returns `{results:[{name, ok, detail}]}`. A failed entry does not stop the batch.
The script skips an entry whose requirement failed, and says which one in `detail`.

When every call is done, run `setup.sh status` again and print the final table. Then list each
failed entry with its `detail`, exactly as returned. A `detail` that starts with `sudo needs a
password` or `sudo is not installed` holds a command for the user: print it as the user's next step.
Any other `detail` names the command and its first error line: print it as returned.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `{"error":"jq_missing"}` | `jq` is the one tool the script needs to run. Tell the user to install it (`brew install jq` or `sudo apt-get install -y jq`) and run `/bf:setup` again. |
| `no_brew` | Print the hint for the user. Do not install anything, not even the git tools. |
| `unsupported_platform` | Say that `/bf:setup` installs with brew on macOS and apt on Linux. List the missing tools from the status table so the user can install them by hand. |
| `sudo -n` cannot run on Linux | Print the `! sudo ...` line from `detail` exactly as returned. The user runs it, then runs `/bf:setup` again. When `detail` says sudo is not installed, the user runs the line as root. |
| A clone fails (network) | Report the `detail`. The tools that need it show as skipped. A re-run retries them. |
| Nothing is missing | Print the table and say so. Run no install command. |
| The user declines | Install nothing. The table already shows what is missing. |
| `python3-modern` still missing after the install | The distro's `python3` is older than 3.11, as on Ubuntu 22.04. Tell the user to install Python 3.11 or newer by hand (for example from the deadsnakes PPA) and run `/bf:setup` again. |
| A re-run after a partial install | The plan holds only what is still missing. Entries that succeeded do not run again. |
