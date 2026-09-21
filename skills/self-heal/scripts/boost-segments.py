#!/usr/bin/env python3
"""Re-segment issue bodies the delimiter sniffer could not split, using TypeSafe.

Reads the stage-A item array on stdin, writes the same shape on stdout. Every
failure path prints the input unchanged: no key, boosting off, API down, a reply
that does not parse. `harvest-issues.sh` is identical without TypeSafe.

Scope is deliberately narrow -- only issues the deterministic segmenter left as a
single item. Where `### ` or `- **` headings exist, the sniffer is already right
and cheaper, so it keeps those untouched.

Code owns the text: it enumerates candidate boundary lines and slices the
original string at the accepted ones. The judgment only picks among lines that
are already there, so no item body can differ from what the issue says.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASK = os.environ.get(  # env override is the test seam -- unset in normal runs
    'TYPESAFE_ASK',
    os.path.join(HERE, '..', '..', 'typesafe', 'scripts', 'typesafe-ask.sh'),
)
CACHE = os.path.expanduser('~/.bf/cache/typesafe-segments.json')

# A body shorter than this is one suggestion whatever its shape.
MIN_CHARS = 400
MAX_CANDIDATES = 40
# Asymmetric on purpose, following the autoformat cookbook: a line that already
# follows a blank line is typographically a fresh start, so it needs less
# evidence than one continuing a block. NEITHER NUMBER IS CALIBRATED -- they are
# starting points to evaluate against real bodies, not constants to trust.
ACCEPT_AFTER_BLANK = 0.5
ACCEPT_MID_BLOCK = 0.7

MARKER = re.compile(r'^(#{2,4}\s+|[-*]\s+|\d+\.\s+|\*\*.+\*\*:?\s*$)')


def headline(chunk):
    """Same rule as the jq `headline` function, for chunks jq never sees."""
    first = chunk.split('\n')[0]
    first = re.sub(r'^### |^- ', '', first).replace('**', '').strip()
    return first[:87] + '...' if len(first) > 90 else first


def candidates(lines):
    """Lines that could open a new item. Over-generate; the judgment prunes."""
    out = []
    for i, line in enumerate(lines):
        if i == 0 or not line.strip():
            continue
        after_blank = not lines[i - 1].strip()
        if after_blank or MARKER.match(line):
            out.append((i, after_blank))
    return out[:MAX_CANDIDATES]


def load_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_cache(cache):
    # Best effort: a cache that cannot be written costs a re-ask, nothing more.
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, 'w') as f:
            json.dump(cache, f)
    except OSError:
        pass


def ask(title, body, cands):
    """Return accepted line numbers, or None when TypeSafe is unavailable."""
    lines = body.split('\n')
    numbered = '\n'.join(f'{i}: {l}' for i, l in enumerate(lines))
    questions = {
        f'b{i}': {
            'type': 'noul',
            'instructions': (
                f'In the numbered issue body, line {i} begins a new, self-contained '
                f'suggestion: a separate piece of work someone could act on without '
                f'having read the lines above it.'
            ),
            'criteria': {
                'true': 'line {} starts a distinct item'.format(i),
                'false': 'line {} continues, elaborates on, or gives an example for '
                         'the item above it'.format(i),
            },
        }
        for i, _ in cands
    }
    state = {'issue_title': title, 'numbered_body': numbered}

    qf = sf = None
    try:
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
            json.dump(questions, f)
            qf = f.name
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
            json.dump(state, f)
            sf = f.name
        r = subprocess.run(
            ['bash', ASK, '--questions', qf, '--state', sf],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            return None
        answers = json.loads(r.stdout)
    except (OSError, ValueError):
        return None
    finally:
        for p in (qf, sf):
            if p:
                try:
                    os.unlink(p)
                except OSError:
                    pass

    accepted = []
    for i, after_blank in cands:
        a = answers.get(f'b{i}')
        if not isinstance(a, dict):
            continue
        p = a.get('noul')
        bar = ACCEPT_AFTER_BLANK if after_blank else ACCEPT_MID_BLOCK
        if isinstance(p, (int, float)) and p >= bar:
            accepted.append(i)
    return accepted


def resegment(item, cache):
    """Return replacement items for a single-item issue, or None to leave it."""
    body = item['full']
    lines = body.split('\n')
    cands = candidates(lines)
    if len(cands) < 2:
        return None

    # Cached by body digest so the `--item` fix pass slices exactly where the
    # scoring pass did. Without this an id like "34:3" could point at different
    # text between two runs, and self-heal would fix something it never scored.
    key = hashlib.sha256(body.encode('utf-8')).hexdigest()
    if key in cache:
        accepted = cache[key]
    else:
        accepted = ask(item['issue_title'], body, cands)
        if accepted is None:
            return None
        cache[key] = accepted

    if len(accepted) < 1:
        return None

    bounds = [0] + [i for i in accepted if 0 < i < len(lines)]
    chunks = []
    for n, start in enumerate(bounds):
        end = bounds[n + 1] if n + 1 < len(bounds) else len(lines)
        chunk = '\n'.join(lines[start:end]).strip()
        if chunk:
            chunks.append(chunk)
    if len(chunks) < 2:
        return None

    return [
        dict(item, id=f"{item['issue']}:{n + 1}", item_index=n + 1,
             title=headline(c), full=c)
        for n, c in enumerate(chunks)
    ]


def main():
    try:
        items = json.load(sys.stdin)
    except ValueError:
        return 1
    if not isinstance(items, list):
        return 1

    counts = {}
    for it in items:
        counts[it.get('issue')] = counts.get(it.get('issue'), 0) + 1
    target_ids = {
        it['id'] for it in items
        if counts.get(it.get('issue')) == 1 and len(it.get('full', '')) >= MIN_CHARS
    }
    if not target_ids:
        print(json.dumps(items))
        return 0

    cache = load_cache()
    before = dict(cache)
    out, boosted = [], 0
    for it in items:
        repl = resegment(it, cache) if it['id'] in target_ids else None
        if repl:
            out.extend(repl)
            boosted += 1
        else:
            out.append(it)
    if cache != before:
        save_cache(cache)

    if boosted:
        print(f'boost-segments: re-split {boosted} issue(s) TypeSafe judged multi-item',
              file=sys.stderr)
    print(json.dumps(out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
