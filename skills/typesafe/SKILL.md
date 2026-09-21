---
name: typesafe
description: Use when the user wants to turn TypeSafe (System One / Jev) boosting on or off for this plugin, check whether their API key works, or understand what boosting changes. Opt-in only — bf works identically without it.
model: sonnet
argument-hint: "[status | on | off] (default: status)"
allowed-tools: Read, Bash(bash *), Bash(jq *), Bash(git *)
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Turn **TypeSafe boosting** on or off. Boosting is opt-in: when it is off, unconfigured, or the API
is unreachable, every boosted call site runs the deterministic code it would have run anyway. A
user without a key sees exactly the plugin everyone else sees — this skill exists so that choice is
explicit and verified, not silent.

## On Invocation

Print banner (plain text):

```
── bf:typesafe ──────────────────────────────────────
```

Take the action from `$ARGUMENTS`: `status` (default), `on`, or `off`. Anything else — run
`status` and say what you did.

## Phase 1 — Act

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/typesafe/scripts/typesafe-setup.sh" <action>
```

The script owns every mechanical step: reading `~/.bf/config.json`, resolving which env var holds
the key, making the live smoke call, and merging the flag back without disturbing other settings
(`parallel_audit` and anything else stay put). Do not hand-roll any of it, and **never print or
echo the key** — the script deliberately reports only `key_present`.

Returns `{action, enabled, api_key_env, key_present, model, config, smoke:{ran,ok,detail}}`.

`on` writes the flag **only if the smoke call answers**. A key that does not work therefore cannot
be enabled — which is the point: a typo'd key that wrote a happy flag would degrade every later run
silently.

## Phase 2 — Report

| Result | Say |
|---|---|
| `on`, `smoke.ok: true` | Boosting is on, the key answered, and name what gets boosted (below). |
| `on`, `key_present: false` | The key is not in this shell. Tell them to export `$<api_key_env>` and re-run — offer `--key-env <VAR>` if their key lives elsewhere. Nothing was written. |
| `on`, `smoke.ok: false` with a key | Quote `smoke.detail`. Auth rejected means the key is wrong; a rate limit or timeout means try again. Nothing was written. |
| `off` | Boosting is off. State that every call site falls back to its deterministic path, and that the config keeps the key env var name for next time. |
| `status`, `enabled: true` | Report the smoke result — a stale key shows up here, not mid-run. |
| `status`, `enabled: false` | Report off, and that `/bf:typesafe on` needs `$<api_key_env>` exported. |

Then, whenever boosting ends up **on**, list what it changes. Keep this list honest — only name
call sites that actually call the helper today:

| Call site | Without boosting | With boosting |
|---|---|---|
| `/bf:self-heal` — `harvest-issues.sh` | An issue body using neither `### ` nor `- **` is one lump item, so it is scored and selected whole | Bodies the sniffer could not split get re-split at judged item boundaries; ids are cached by body digest so the fix pass slices where the scoring pass did |
| `/bf:self-audit` — `audit-static.sh` | A hardcoded word list (`path`, `foo`, `your`…) guesses which unresolved `x/SKILL.md` refs are prose; the rest are filed as findings | Unresolved refs are judged real-vs-illustrative, and suppressions are counted in `notes[]` so two runs stay explainable |
| `/bf:feature`, `/bf:micro`, `/bf:review` — `check-report-status.sh` | A report that drifted from `STATUS: X` reads as `NOT_FOUND`, indistinguishable from a missing report — the gate opens silently | The verdict is read out of the prose; an unconfident answer still returns `NOT_FOUND` |

Everything else — `detect-stack.sh`, `scope.sh`, git and GraphQL plumbing — stays deterministic and
always will. Exact lookups do not want a judgment.

## For skill authors — calling the helper

One entry point, from any script or skill:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/typesafe/scripts/typesafe-ask.sh" \
  --questions /tmp/q.json --state /tmp/state.json
```

Exit `0` → the `answers` object on stdout. Exit `3` → **unavailable, fall back** — disabled, no
key, non-2xx, timeout, malformed reply. The reason goes to stderr and the caller does not branch on
it. Exit `2` is a usage bug in the caller, not a fallback condition.

Three rules for a boosted call site:

1. **The fallback is today's behaviour, unchanged.** Boosting refines a result the deterministic
   path already produces. If removing TypeSafe would break the call site, it is a dependency, not a
   boost — do not ship it.
2. **Never let a judgment reach an `audit_id`.** Those fingerprints in
   `skills/self-audit/scripts/audit-static.sh` exist so later runs dedupe against already-filed
   issues. A nondeterministic input there re-files the same finding forever.
3. **Keep the timeout.** `/bf:autopilot` runs unattended; the helper caps every request, and a
   call site must not wrap it in a retry loop that undoes the cap.

Question shapes (`choice`, `noul`, `score`), criteria formats and confidence semantics are at
<https://docs.typesafe.ai> — read the primitive page before writing a new question rather than
copying a shape from memory.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `~/.bf/config.json` is malformed JSON | Script exits `{"error":"config_malformed"}`. Do not rewrite the file — report it and let the user fix or move it; it holds their other settings. |
| `jq` or `curl` missing | Reported as an error (setup) or as unavailable (helper). Boosting stays off; nothing else in bf is affected. |
| Key exported in a different shell than the one Claude runs | `key_present: false` despite the user "having set it". Point at their shell profile, not at the key. |
| User asks to store the key in the config file | Decline and explain: the config is world-readable in `$HOME` and gets pasted into issues. The env var name is stored; the key is not. |
| `off` when no config exists | Nothing to write; report off. The absence of config already means off. |
| Rate limited during a real run | The call site falls back silently by design. It is not an error to report mid-workflow. |
