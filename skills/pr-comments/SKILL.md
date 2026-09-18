---
name: pr-comments
description: Use when a PR has review feedback to work through — "address the PR comments", "handle the review feedback", "respond to CodeRabbit", "what did the reviewer say". Triages every comment on its merits rather than obeying it: escalates contested ones to bf:consilium, then fixes, argues back, or defers each one. A fix covers every instance the PR introduced, not just the line the reviewer happened to spot. Replies and resolutions post as one approved batch.
model: opus
disable-model-invocation: false
argument-hint: "[empty for the current branch's PR | <pr number> | <pr url>] [--wait]"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(bash *), Bash(git *), Bash(gh *), Bash(mkdir *), Bash(jq *), Task, Skill
---

Read `${CLAUDE_PLUGIN_ROOT}/conventions/plugin-main.md` first.

Work through the review feedback on a pull request — line-anchored threads, PR-level comments and
review summaries, from humans and bots alike — deciding each one on its merits. A reviewer's
suggestion is an argument, not an instruction: some are right, some are right about the problem and
wrong about the fix, and some are wrong. Applying all three blindly is how review makes code worse.

**Not `/bf:review`.** That one *produces* findings on a change. This one *responds* to findings
someone else already left, and never opens new review threads of its own.

Every reply and every thread resolution is outward-facing and public. Nothing reaches GitHub until
one closing gate is approved.

## On Invocation

Print banner (plain text, not in a code block):

```
── bf:pr-comments ─────────────────────────────────────
```

Fetch everything in one call — never assemble threads from separate `gh` queries:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pr-comments/scripts/fetch-pr-comments.sh" "$ARGUMENTS"
```

It returns `{pr, url, title, head_sha, viewer, base, head, threads[], files[], counts{}, notes[]}`.
`files[]` is the PR's changed files as `{path, additions, deletions, change_type}` with `DELETED`
ones dropped — that list is the search surface for Phase 3's generalization pass, so do not rebuild
it with `git diff` against a guessed base. Each
`threads[]` entry is `{kind, thread_id, comment_id, file, line, side, outdated, resolved, author,
is_bot, body, replies[], diff_hunk, answered_by_viewer}`, where `kind` is:

| `kind` | What it is | Resolvable |
|--------|-----------|------------|
| `thread` | Line-anchored review thread — has `file`, `line`, `diff_hunk` | yes |
| `issue` | PR-level comment, not anchored to code | no |
| `review` | A review's summary body | no |

The script drops resolved threads and threads whose conversation already contains a reply from
`viewer`, so a second run does not double-post to a public PR. `notes[]` says what it dropped;
print those lines. Pass `--all` only when the user explicitly asks to revisit answered or resolved
feedback.

On `{"error": ...}`: print `detail` and stop.

If `counts.actionable` is `0`, check whether a review is still running — a bot's "started
reviewing" status post, or any returned body that reads as a review-in-progress marker. If one is
there the run is early, not done:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pr-comments/scripts/wait-for-review.sh" "$ARGUMENTS" --timeout 600
```

Run it without asking when `$ARGUMENTS` contains `--wait`; otherwise ask once whether to wait up to
ten minutes for the review to land. Never hand-roll the loop — one that watches only for findings
hangs silently through a review that fails or is abandoned. Act on `status`:

| `status` | Do |
|----------|-----|
| `findings` | Re-run the fetch above and continue the normal flow. |
| `review_settled` | The review finished with nothing actionable — print `STATUS: NO_OPEN_COMMENTS` and stop. |
| `timeout` | Report how long it waited and that the review never landed; it may have failed. Stop rather than guess at findings. |

With nothing actionable and no in-progress marker, print `STATUS: NO_OPEN_COMMENTS` and stop —
read nothing, spawn nothing.

Then print one line: `PR #<pr> "<title>" — <actionable> open comment(s), <bot> from bots`.

Resolve the artifact root (2-step lookup in `plugin-main.md`), `mkdir -p` the `.bf/pr-comments/`
directory under it, and use `<pr>-triage.md` there as the triage file for this run. If it already
exists, read it first — entries already carrying a `posted` marker are done; do not re-triage them.

## Phase 1 — Ground each comment in the code

A comment is judged against what the code actually says now, not against `diff_hunk`. The hunk is a
snapshot from when the comment was written and `outdated: true` means the lines have since moved.

For each comment: read the file around `line` (or, for `issue`/`review` comments, the files the body
names), and read `replies[]` — a thread may already contain the counter-argument or the author's own
answer. Load the conventions the comment touches via the 3-step lookup in `plugin-main.md` (`dev`,
`code-review`, `testing`, `architecture`, plus anything `/bf:scan-conventions` surfaces). A
reviewer's stylistic preference that contradicts a project convention loses to the convention, and
that is the argument to make in the reply.

Group comments that make the same point across files, and triage the group once. Reviewers repeat
themselves; so do bots. **A group is one verdict over many threads, never one thread standing in for
the others** — carry every member's `thread_id` on the grouped entry. Each of those threads is
public, and each still needs its own reply and its own resolve in Phase 5; a group that loses a
thread id leaves that thread open forever with its concern already fixed.

## Phase 2 — Triage

Assign each comment exactly one verdict. This set is fixed — do not invent a sixth.

| Verdict | Meaning | Reply? | Resolve? |
|---------|---------|--------|----------|
| `accept` | The suggestion is right; do it as described. | optional | yes, after the fix |
| `accept-different` | The reviewer found a real problem but the wrong fix. Fix it your way. | **required** — say what you did instead and why | yes, after the fix |
| `reject` | The suggestion is wrong, or costs more than it buys. Change nothing. | **required** — the argument | no — the reviewer closes it |
| `defer` | Valid, but out of scope for this PR. | **required** — where it went | no |
| `question` | Cannot be judged without the reviewer. | **required** — the question | no |

Two rules that decide most of the hard cases:

- **`accept` needs a reason too, not just assent.** State in one line why the suggestion is right.
  A verdict you cannot justify is one you have not checked, and "the reviewer said so" is exactly
  the reasoning this skill exists to replace.
- **Bots get the same standard, not a lower one.** A bot comment is a static-analysis guess about
  code it has not run, so its reject rate is legitimately higher — but reject it for a stated
  reason, never for being a bot. Bot replies are terse: nobody is reading them for tone, and there
  is no conversation to sustain.

**Never mark `reject` on a correctness claim you have not disproved in the code.** If the reviewer
says a branch can be reached with a null and you cannot show it cannot, that is `accept` or
`question` — not a rejection with a confident-sounding paragraph. This is the failure mode of a
skill built to push back, and it is worse than obeying, because a wrong rejection is public and
argued.

**Check the class before rejecting.** Run steps 1 and 2 of the generalization pass in Phase 3 first.
If the pattern appears elsewhere in the PR's changed lines and the reviewer's concern is valid
*there*, the verdict is not `reject` — fix the sibling, and reply that the commented line
specifically is fine and why. A rejection that is right about the line and wrong about the class is
the most expensive mistake available here: it is public, it is argued, and it leaves the real
instance sitting in the branch.

### Escalation

Run `Skill("bf:decide", args=...)` inline for any comment where the verdict is not obvious after
reading the code. Escalate to `bf:consilium` when **either** holds:

- `bf:decide` returned `low` confidence, or
- the comment objects to a design or architecture choice rather than to a line of code — the
  reject-versus-rework calls that are expensive to get wrong.

`bf:consilium` has `disable-model-invocation: true`, so it only runs when called explicitly, and it
needs the **embedded payload format** — free-form text sends it down the standalone path, where it
stops to ask the user a clarifying question mid-run:

```
QUESTION: <the reviewer's objection, as a decision — e.g. "Split OrderService per the reviewer, or keep it and reply?">
PHASE: pr-comments triage
SESSION_LOG: <absolute path to the triage file>
OPTIONS: A) accept | B) accept-different: <what instead> | C) reject: <argument>
CONTEXT:
<the comment body, the code it points at, and the convention or constraint in play>
```

Passing the triage file as `SESSION_LOG` puts the verdict in that file's `## Decisions` block
(accumulate mode — see the Block Writing Pattern in `plugin-main.md`), which is what makes an
argued rejection auditable after the fact. Its `**Why:**` prose must follow the Durable Record
Phrasing rule — plain engineering rationale, no skill or critic names, since a reply drafted from it
gets posted publicly.

Render the triage as one table, then write it to the triage file under a `## Triage` header of its
own — the `## Decisions` block that escalations append to is inserted before the next `^## `
boundary, and a table sitting outside a header of its own is where that insert lands. Marking
entries `posted` later is an in-place edit of that block, never a rewrite of the file.

The table:

```
#  file:line                    author         verdict            what happens
1  src/net/retry.ts:42          babakks        accept             cap comes from config
2  src/order/service.ts:88      coderabbitai   reject             the guard is unreachable — arg in reply
3  src/api/handler.ts:12        babakks        accept-different   fix at the caller, not here
4  src/{a,b}/parse.ts:12,31     babakks ×2     accept             same missing guard — 2 threads
```
Row 4 is a grouped entry: one verdict, two threads, and both thread ids recorded on it.

## Phase 3 — Fix the class, not the line

Apply the `accept` and `accept-different` fixes. Follow the `dev` and `testing` conventions; run the
project's tests and lint as those conventions require, and report failures rather than posting a
reply that claims a fix that does not build.

**A review comment is a sample, not an inventory.** Reviewers spot-check — they read until they hit
an instance, comment on that one, and move on. The line they pointed at is rarely the only place the
problem occurs, so fixing exactly that line and resolving the thread leaves the PR carrying the same
defect wherever the reviewer happened not to look — now with a resolved thread implying it was
handled.

For every `accept` and `accept-different` fix, run a generalization pass:

1. **Name the class.** State the defect as a rule, not a location — "the retry ceiling is a literal
   instead of config", not "line 42 is wrong". A defect you cannot state as a rule is a one-off, and
   the pass ends here.
2. **Search the surface.** Derive a signature from the class and `Grep` the paths in `files[]` for
   it. Search for the *pattern* — the call shape, the missing guard, the unchecked return — never
   the literal text of the commented line, which by definition occurs once. A grep hit is a lead:
   read each candidate before counting it an instance.
3. **Fix every instance the PR introduced or touched**, then verify each one the same way as the
   original.

**The boundary is the PR's own changed lines, not its changed files.** An instance in code this PR
did not touch is `defer` — even in a file the PR edits, even when it is unmistakably the same
defect. A three-line hunk in a four-hundred-line file does not make the other lines this PR's
business. Widening past that turns a review fix into an unrequested refactor the reviewer now has to
re-review, which is the failure this pass has to avoid while still being thorough.

**Cap: about 5 sibling sites.** Past that the class is a refactor rather than a review fix — hand it
to `bf:decide`, and expect the answer to be fix the commented site now and `defer` the class with a
reply saying where it went. The number is a chosen default, not derived from anything; tune it if it
splits classes that should have been fixed whole.

Re-read each edited unit once and check it against the comment as stated. **A resolution says the
thread's concern is gone** — resolving on an unverified fix is a false public claim, so a fix that
did not verify drops back to `question` or stays open with an honest reply.

## Phase 4 — Draft the replies

One reply per comment that needs one. Address the reviewer's actual point; a reply that restates the
comment and adds "fixed" is noise.

- **Any fix that widened** — name the other sites, with paths. A reviewer who pointed at one line
  and got four fixed will otherwise re-read that one line, resolve, and never learn the rest of the
  change happened. This disclosure is what keeps a widened fix reviewed instead of silent, so it is
  required even where the reply was otherwise optional — an `accept` that widened now needs one.
- **`accept-different`** — what you did instead, and the reason. This is the reply that most often
  prevents a second round.
- **`reject`** — the argument and its evidence: the convention by name or topic, the code path that
  makes the concern unreachable, the measurement. Never "this is fine" or "out of scope" alone. No
  internal process vocabulary and no spec IDs (Durable Record Phrasing) — the reviewer has none of
  that context.
- **`defer`** — where it went. If the user wants an issue filed, `/bf:gh` does that; do not open one
  unasked.
- **`question`** — one question, specific enough to answer in a sentence.

Plain prose, a couple of sentences, no headers or bullet scaffolding. Show every draft in full
before the gate — this is the text that gets published under the user's name.

## Phase 5 — Closing gate

Ask exactly ONE question over the whole batch, then wait:

> Post <N> replies and resolve <M> threads?

Never one question per comment: it breaks the one-question rule and is unusable at fifteen comments.
`/bf:autopilot pr-comments <args>` is the hands-off path.

On approval, write the plan and post it in one call:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pr-comments/scripts/post-replies.sh" <plan.json> "$ARGUMENTS"
```

`plan.json` is an array of `{kind, thread_id, reply, resolve}` in triage order — write it under
`.bf/pr-comments/`. **One entry per thread, not per triage row.** A grouped row fans back out here:
each `thread_id` it carries gets its own entry, so every reviewer reads the answer on the thread
they wrote and every thread resolves. The replies may be near-identical — that is fine, and far
better than a thread left open because another thread answered for it. `resolve: true` only for verified `accept`/`accept-different` entries on `kind:
thread`; the script skips resolution on `issue` and `review` entries, which have no thread. Add
`--dry-run` to print what would be sent without sending it.

The result is `{posted, resolved, skipped, failed, results[]}`. Report it as-is: mark the posted
entries in the triage file, and name any `failed` entry with its detail rather than reporting the
batch as done. If the user declines the gate, the triage file and the fixes stay — nothing was
published, and a rerun picks up from the file.

Committing and pushing the fixes is not part of this skill. Say in one line that the working tree
has unpushed fixes, so the reviewer is looking at replies that reference code they cannot see yet.

## Edge Cases & Errors

| Condition | Handling |
|-----------|----------|
| `gh` missing or unauthenticated | The script returns `gh_missing` / `gh_unauthenticated`. Print `detail` and stop — `gh` is a stated bf requirement |
| No PR for the current branch | `no_pr`. Ask for a PR number or URL — one question |
| `counts.actionable` is `0`, no review in flight | `STATUS: NO_OPEN_COMMENTS` and stop. Do not go looking for feedback elsewhere |
| `counts.actionable` is `0` but a review is still running | Wait via `wait-for-review.sh` (see the fetch step), then act on its `status` |
| Thread is `outdated: true` | The code moved after the comment. Judge the current code; if the concern no longer applies, that is a reply saying so, not a silent resolve |
| Comment asks for something already done in a later commit | Reply pointing at the commit, then resolve. Do not redo the work |
| `counts.files_truncated` is `true` | The PR touches more than 100 files, so `files[]` is partial and the generalization pass cannot see the whole surface. Say so in the output and treat every widened fix as best-effort rather than exhaustive |
| A sibling instance sits in code the PR did not touch | `defer` it — say in the reply that the pattern predates the PR and where it lives. Do not fix it here, and do not let it block resolving the thread |
| Generalization pass finds more than ~5 siblings | Escalate the class to `bf:decide`. Fix the commented site, `defer` the class, and say both in the reply — never silently refactor past the cap |
| A grouped triage row reaches Phase 5 | Fan it out to one plan entry per `thread_id`. Verify the plan's entry count against the number of threads in scope, not the number of triage rows — they differ exactly when grouping happened |
| More than ~30 open comments | Group aggressively in Phase 1, triage the groups, and say in the output that comments were grouped. Do not silently drop the tail |
| A reply fails to post but its thread resolved (or vice versa) | The `results[]` entry shows the split. Report it and leave the triage file unmarked for that entry — a rerun retries only what failed |
| Reviewer has already replied since the fetch | The rerun's `answered_by_viewer` filter does not cover reviewer replies. On a `failed` post, refetch before retrying so the reply lands in context |
| User wants to argue with a verdict at the gate | Take the correction, redraft that reply, and re-ask the gate once — the batch stays intact |
