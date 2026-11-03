# Waiting for a review in progress

If `counts.actionable` is `0`, check whether a review is still running — a bot's "started
reviewing" status post, any returned body that reads as a review-in-progress marker, or a `notes[]`
line saying the bot last reviewed an older commit than the head (`last_bot_review.sha` !=
`head_sha`). If one is there the run is early, not done — though a stale-review note only means a
re-review may come, and some bots never re-review on push, which is why the wait follows the
consent rule below rather than running automatically:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pr-comments/scripts/wait-for-review.sh" "<url>" --timeout 600
```

Run it without asking when `$ARGUMENTS` contains `--wait`; otherwise ask once whether to wait up to
ten minutes for the review to land. Never hand-roll the loop — one that watches only for findings
hangs silently through a review that fails or is abandoned. Act on `status`:

| `status` | Do |
|----------|-----|
| `findings` | Re-run the `fetch-pr-comments.sh <<'BF_ARGS'` call in SKILL.md and continue the normal flow. |
| `review_settled` | The review finished with nothing actionable — print `STATUS: NO_OPEN_COMMENTS` and stop. |
| `timeout` | Report how long it waited and that the review never landed; it may have failed. Stop rather than guess at findings. |

Some review bots keep one standing PR-level comment — "no findings", a status summary — and may
publish their actual result as a CI check. That comment comes back as an actionable `issue` thread, so
`wait-for-review.sh` reports `findings` on its first poll even while the review is still running. When
every actionable thread is a bot `issue` comment that reads as a status post, look at the checks:

```bash
gh pr checks <pr> --json name,bucket
```

If the bot's check has `bucket: "pending"`, wait for it with gh's own loop rather than a hand-rolled
one — under the same consent rule as the `wait-for-review.sh` wait above (run without asking when
`$ARGUMENTS` contains `--wait`, otherwise ask once) — then re-run the `fetch-pr-comments.sh <<'BF_ARGS'` call in SKILL.md:

```bash
gh pr checks <pr> --watch --interval 30 > /dev/null
```

`--watch` has no timeout of its own and waits on every check, so run it with a 600000 ms Bash
timeout. If it is still running at that point, stop it and re-run `gh pr checks <pr> --json name,bucket`:
an unrelated slow job can outlast the bound while the bot's check has already finished. Only if the
bot's check is still pending, handle it as the `timeout` row above.

When the bot has no check (none matches it, or gh reports no checks) or its check is not pending, at
the first look or after the wait, the status post is the result, but only if its `updated_at` is later than the fetch
result's `head_pushed_at` (when the head was pushed; `null` when unknown). A post that is older, or has no time to compare, is stale: triage it in
the normal flow instead. For a current post: if every such post reports no open
findings, print `STATUS: NO_OPEN_COMMENTS` and stop without triaging them; if one lists findings,
continue the normal flow.
