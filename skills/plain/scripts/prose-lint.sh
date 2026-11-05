#!/usr/bin/env bash
# Lint text against the hard markers and word lists of the resolved prose.md.
#
# Usage: prose-lint.sh <file|-> [--mode file|chat|commit|comment] [--rules <prose.md>]
#                      [--cwd <dir>] [--ext sh|py|ts|js] [--format text|json]
#        prose-lint.sh --digest [--rules <prose.md>] [--cwd <dir>]
#        prose-lint.sh --classify <path>
#        prose-lint.sh --selftest
# Output: json: one object {hard:{em_dash,semicolon,contraction}, soft:{replace,banned,long_sentence},
#         words, long_reply, rules_block, summary, hard_summary}. hard_summary counts only the markers in
#         the hard list. rules_block is true when the resolved file has a
#         prose-lint block. text: one finding per line, "<line>: <marker>: <text>". --digest prints the
#         Self-lint section of the resolved prose.md.
#         --classify prints the mode and extension for a path ("file" or "comment sh"), and exits 1 with
#         no output when the lint does not support the path. This script owns the list of supported files.
# Exit:   0 no hard marker, 1 at least one hard marker, 2 usage or runtime error. Only a hard marker
#         decides the exit code, never a score or a ratio, and a soft finding never does.
# Errors: {"error":...,"detail":...} on stderr + exit 2.
set -euo pipefail
export LC_ALL=C

self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
resolver=$(cd "$(dirname "$self")/../../scan-conventions/scripts" && pwd)/resolve-conventions.sh

# Without jq, die prints the same JSON by hand, so a usage error still exits 2 (never 127).
die() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg e "$1" --arg d "$2" '{error:$e, detail:$d}' >&2
  else
    printf '{"error":"%s","detail":"%s"}\n' "$1" "$(printf '%s' "$2" | sed 's/[\\"]/\\&/g')" >&2
  fi
  exit 2
}

# One row per hard marker: name|singular|plural. A new hard marker needs a row here and an emit call below.
hard_table='em_dash|em dash|em dashes
semicolon|semicolon|semicolons
contraction|contraction|contractions'

# The selftest fixtures run the script as a child process, so the real command line is the test seam.
selftest() {
  local fails=0 out rc
  tmp=$(cd "$(mktemp -d)" && pwd -P)
  trap 'rm -rf "$tmp"' EXIT
  eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails+1)); fi; }
  run() { rc=0; out=$(bash "$self" "$@" 2>/dev/null) || rc=$?; }
  # lint_text <text> <args...>: the text goes in on stdin.
  lint_text() { local t=$1; shift; rc=0; out=$(printf '%s\n' "$t" | bash "$self" - "$@" 2>/dev/null) || rc=$?; }
  jf() { jq -r "$1" <<<"$out"; }
  nwords() { local i=0 w=; while [ "$i" -lt "$1" ]; do w="$w word"; i=$((i+1)); done; printf '%s' "${w# }"; }

  local dash=$'\xE2\x80\x94' curly=$'\xE2\x80\x99'
  local full=$tmp/full.md noblock=$tmp/noblock.md dashonly=$tmp/dashonly.md dashnosec=$tmp/dashnosec.md
  st_fixtures
  st_hard
  st_rules_block
  st_classify
  st_errors
  st_soft
  st_modes
  st_digest
  st_real_rules

  [ "$fails" -eq 0 ]
}

st_fixtures() {
  cat > "$full" <<'EOF'
# Fixture rules

## Self-lint

Check these.

1. First item.
2. Second item.

## Limits

Other text.

```prose-lint
hard: em_dash semicolon contraction
cap_instruction: 20
cap_descriptive: 25
long_reply_words: 150
replace: utilize>use prior_to>before
banned: robust worth_noting
```
EOF
  printf '# Fixture\n\nNo block here.\n' > "$noblock"
  sed 's/^hard: .*/hard: em_dash/' "$full" > "$dashonly"
  printf '# Fixture\n\n```prose-lint\nhard: em_dash\n```\n' > "$dashnosec"
}

st_hard() {
  lint_text "A${dash}B" --rules "$full" --format json
  eq "em dash exit" "$rc" 1; eq "em dash count" "$(jf .hard.em_dash)" 1
  lint_text "one; two" --rules "$full" --format json
  eq "semicolon exit" "$rc" 1; eq "semicolon count" "$(jf .hard.semicolon)" 1
  lint_text "We don't go." --rules "$full" --format json
  eq "contraction exit" "$rc" 1; eq "contraction count" "$(jf .hard.contraction)" 1
  lint_text "We don${curly}t go." --rules "$full" --format json
  eq "curly apostrophe" "$(jf .hard.contraction)" 1
  lint_text "It's late. That's fine. Here we go." --rules "$full" --format json
  eq "It's and That's" "$(jf .hard.contraction)" 2
  lint_text "It's what's here." --rules "$full" --format json
  eq "adjacent 's forms" "$(jf .hard.contraction)" 2
  lint_text "The parser's output and the dogs' bowls." --rules "$full" --format json
  eq "possessive exit" "$rc" 0; eq "possessive count" "$(jf .hard.contraction)" 0
  lint_text "Use the 'main' branch when the job is 'done' and 'really' ready." --rules "$full" --format json
  eq "single-quoted words" "$(jf .hard.contraction)" 0
  lint_text $'```\na; b\n```\nUse `x; y` here.' --rules "$full" --format json
  eq "fence and code span ignored" "$(jf .hard.semicolon)" 0
  lint_text 'Use &lt;div&gt; and &#123; and &#x1F; and &nbsp; here.' --rules "$full" --format json
  eq "html entity is not a semicolon" "$rc" 0; eq "html entity count" "$(jf .hard.semicolon)" 0
  lint_text 'Use &lt;div&gt; here; then stop. Also a; b.' --rules "$full" --format json
  eq "semicolon beside an entity still counts" "$(jf .hard.semicolon)" 2
  lint_text 'AT&T; then R&D; ok.' --rules "$full" --format json
  eq "a one-letter name after & is not an entity" "$(jf .hard.semicolon)" 2
  lint_text $'| a | b; c |\n|---|---|' --rules "$full" --format json
  eq "table row counts" "$(jf .hard.semicolon)" 1
  lint_text "> quoted; text" --rules "$full" --format json
  eq "blockquote ignored" "$(jf .hard.semicolon)" 0
}

st_rules_block() {
  lint_text "a; b${dash}c" --rules "$noblock" --format json
  eq "no block rules_block" "$(jf .rules_block)" false
  eq "no block counts all markers" "$(jf '.hard.semicolon + .hard.em_dash')" 2
  eq "no block exit" "$rc" 1
  lint_text "We utilize robust parts; fine." --rules "$noblock" --format json
  eq "no block no soft lists" "$(jf '.soft.replace + .soft.banned')" 0
  lint_text "one; two" --rules "$dashonly" --format json
  eq "non-hard marker still counted" "$(jf .hard.semicolon)" 1
  eq "non-hard marker exit" "$rc" 0
  lint_text "plain text" --rules "$full" --format json
  eq "clean exit" "$rc" 0; eq "clean rules_block" "$(jf .rules_block)" true
  lint_text "A${dash}B; C" --rules "$full" --format text
  eq "text format" "$(printf '%s' "$out" | tr '\n' '|')" "1: em_dash: ${dash}|1: semicolon: ;"
  lint_text "A${dash}B; C" --rules "$full" --format json
  eq "summary" "$(jf .summary)" "1 em dash, 1 semicolon, 2 words"
  eq "hard summary" "$(jf .hard_summary)" "1 em dash, 1 semicolon"
  lint_text "one; two${dash}x" --rules "$dashonly" --format json
  eq "hard summary only lists hard-list markers" "$(jf .hard_summary)" "1 em dash"
  sed 's/^hard: .*/hard: semicolon em_dash/' "$full" > "$tmp/swapped.md"
  lint_text "one; two${dash}x" --rules "$tmp/swapped.md" --format json
  eq "hard summary follows the hard list order" "$(jf .hard_summary)" "1 semicolon, 1 em dash"
  eq "summary follows the marker table order" "$(jf .summary)" "1 em dash, 1 semicolon, 2 words"
  eq "json hard keys" "$(jf '.hard | keys_unsorted | join(",")')" "em_dash,semicolon,contraction"
}

st_classify() {
  run --classify a/b.md; eq "classify md" "$out" file
  run --classify a/b.sh; eq "classify sh" "$out" "comment sh"
  run --classify a/b.js; eq "classify js" "$out" "comment js"
  # a PATH without jq: usage errors and the selftest guard must exit 2, never 127
  mkdir -p "$tmp/nojq"
  for t in bash dirname basename sed; do ln -sf "$(command -v "$t")" "$tmp/nojq/$t"; done
  rc=0; PATH=$tmp/nojq bash "$self" --classify >/dev/null 2>&1 || rc=$?
  eq "classify usage error without jq exits 2" "$rc" 2
  rc=0; PATH=$tmp/nojq bash "$self" --selftest >/dev/null 2>&1 || rc=$?
  eq "selftest without jq exits 2" "$rc" 2
  run --classify a/b.json; eq "classify unsupported output" "$out" ""; eq "classify unsupported exit" "$rc" 1
}

st_errors() {
  sed 's/^hard: .*/hard: em-dash/' "$full" > "$tmp/badhard.md"
  lint_text "one; two" --rules "$tmp/badhard.md" --format json
  eq "unknown hard name exits 2" "$rc" 2
  sed 's/^cap_instruction:/cap_instrucion:/' "$full" > "$tmp/badkey.md"
  lint_text "one; two" --rules "$tmp/badkey.md" --format json
  eq "unknown key exits 2" "$rc" 2
  sed 's/^```prose-lint$/```prose-lint-old/' "$full" > "$tmp/oldfence.md"
  lint_text "one; two" --rules "$tmp/oldfence.md" --format json
  eq "prose-lint-old is no block" "$(jf .rules_block)" false
  eq "prose-lint-old keeps hard markers on" "$rc" 1

  run --rules "$full"; eq "no input exits 2" "$rc" 2
  run "$tmp/missing.md" --rules "$full"; eq "unreadable file exits 2" "$rc" 2
  run "$full" --bogus; eq "unknown flag exits 2" "$rc" 2
  run "$full" --mode nope --rules "$full"; eq "unknown mode exits 2" "$rc" 2
  run "$full" --rules "$tmp/missing.md"; eq "unreadable rules exits 2" "$rc" 2
  run "$full" --format yaml --rules "$full"; eq "unknown format exits 2" "$rc" 2
}

st_soft() {
  lint_text "We utilize it." --rules "$full" --format json
  eq "replace word" "$(jf .soft.replace)" 1; eq "soft only exit" "$rc" 0
  lint_text "Do it prior to launch." --rules "$full" --format json
  eq "replace phrase" "$(jf .soft.replace)" 1
  lint_text "A robust tool." --rules "$full" --format json
  eq "banned word" "$(jf .soft.banned)" 1
  lint_text "It is worth noting that." --rules "$full" --format json
  eq "banned phrase" "$(jf .soft.banned)" 1
  lint_text "The utilization is fine." --rules "$full" --format json
  eq "whole word only" "$(jf .soft.replace)" 0
  lint_text "$(nwords 30)." --rules "$full" --format json
  eq "30-word sentence" "$(jf .soft.long_sentence)" 1
  lint_text "1. $(nwords 22)." --rules "$full" --format json
  eq "22-word numbered step" "$(jf .soft.long_sentence)" 1
  lint_text "$(nwords 22)." --rules "$full" --format json
  eq "22-word descriptive" "$(jf .soft.long_sentence)" 0
  lint_text "# $(nwords 40)" --rules "$full" --format json
  eq "long heading" "$(jf .soft.long_sentence)" 0
  lint_text "$(nwords 12)."$'\n'"$(nwords 12)." --rules "$full" --format json
  eq "two short sentences" "$(jf .soft.long_sentence)" 0
  lint_text "$(nwords 30)." --rules "$noblock" --format json
  eq "no block no caps" "$(jf .soft.long_sentence)" 0
  lint_text "We utilize it." --rules "$full" --format json
  eq "soft in summary" "$(jf .summary)" "1 replaceable word, 3 words"
}

st_modes() {
  lint_text "$(nwords 160)." --mode chat --rules "$full" --format json
  eq "long reply" "$(jf .long_reply)" true
  lint_text "$(nwords 160). "$'\n'"| a | b |" --mode chat --rules "$full" --format json
  eq "table cancels long reply" "$(jf .long_reply)" false
  lint_text "$(nwords 160). "$'\n```\ncode\n```' --mode chat --rules "$full" --format json
  eq "fence cancels long reply" "$(jf .long_reply)" false
  lint_text "$(nwords 160)." --mode file --rules "$full" --format json
  eq "file mode no long reply" "$(jf .long_reply)" false
  lint_text "$(nwords 40)." --mode commit --rules "$full" --format json
  eq "commit mode no cap" "$(jf .soft.long_sentence)" 0
  lint_text "fix: a; b" --mode commit --rules "$full" --format json
  eq "commit mode semicolon" "$(jf .hard.semicolon)" 1
  lint_text "\`a; b\`" --mode commit --rules "$full" --format json
  eq "commit mode keeps code spans" "$(jf .hard.semicolon)" 1
  lint_text $'#!/bin/sh; x\n# fine; no' --mode comment --ext sh --rules "$full" --format json
  eq "comment shebang skipped" "$(jf .hard.semicolon)" 1
  lint_text $'echo a; b\n# comment' --mode comment --ext sh --rules "$full" --format json
  eq "comment ignores code lines" "$(jf .hard.semicolon)" 0
  lint_text $'  #count = 0;\n# a `x; y` b' --mode comment --ext ts --rules "$full" --format json
  eq "ts hash is not a comment" "$(jf .hard.semicolon)" 0
  lint_text "// a${dash}b" --mode comment --ext ts --rules "$full" --format json
  eq "ts slash comment" "$(jf .hard.em_dash)" 1
  lint_text '# a `x; y` b' --mode comment --ext py --rules "$full" --format json
  eq "comment code span ignored" "$(jf .hard.semicolon)" 0
  lint_text "# utilize robust" --mode comment --ext sh --rules "$full" --format json
  eq "comment mode hard only" "$(jf '.soft.replace + .soft.banned')" 0
  lint_text "# x" --mode comment --rules "$full" --format json
  eq "comment needs ext" "$rc" 2
}

st_digest() {
  run --digest --rules "$full"
  eq "digest with section" "$(printf '%s' "$out" | tr '\n' '|')" "Check these.||1. First item.|2. Second item."
  run --digest --rules "$noblock"
  eq "digest fallback" "$out" "Hard markers in force: em dash, semicolon, contraction."
  run --digest --rules "$dashonly"
  eq "digest keeps the section with a custom hard list" "$(printf '%s' "$out" | grep -c 'Check these')" 1
  run --digest --rules "$dashnosec"
  eq "digest fallback uses hard list" "$out" "Hard markers in force: em dash."
}

st_real_rules() {
  local real=${self%/skills/plain/scripts/prose-lint.sh}/conventions/prose.md
  if grep -q '^```prose-lint[[:space:]]*$' "$real" 2>/dev/null; then
    lint_text "A robust tool." --rules "$real" --format json
    eq "real file rules_block" "$(jf .rules_block)" true
    eq "real file banned list" "$(jf .soft.banned)" 1
    run --digest --rules "$real"
    eq "real digest items" "$(printf '%s\n' "$out" | grep -c '^[1-8]\. ')" 8
  fi
}

parse_args() {
  mode=file format=text rules= cwd=. ext= input= digest=0
  while [ $# -gt 0 ]; do
    case $1 in
      --mode) [ $# -ge 2 ] || die usage "--mode needs a value"; mode=$2; shift 2 ;;
      --format) [ $# -ge 2 ] || die usage "--format needs a value"; format=$2; shift 2 ;;
      --rules) [ $# -ge 2 ] || die usage "--rules needs a value"; rules=$2; shift 2 ;;
      --cwd) [ $# -ge 2 ] || die usage "--cwd needs a value"; cwd=$2; shift 2 ;;
      --ext) [ $# -ge 2 ] || die usage "--ext needs a value"; ext=$2; shift 2 ;;
      --digest) digest=1; shift ;;
      -) input=-; shift ;;
      -*) die usage "unknown flag: $1" ;;
      *) [ -z "$input" ] || die usage "more than one input"; input=$1; shift ;;
    esac
  done
}

check_options() {
  # One row per mode: input filter, sentence-cap check, long-reply check, soft word check.
  case $mode in
    file) filt=prose caps=1 longreply=0 soft=1 ;;
    chat) filt=prose caps=1 longreply=1 soft=1 ;;
    commit) filt=raw caps=0 longreply=0 soft=1 ;;
    comment) filt=comment caps=0 longreply=0 soft=0 ;;
    *) die usage "unknown mode: $mode" ;;
  esac
  case $format in text|json) ;; *) die usage "unknown format: $format" ;; esac
  if [ "$mode" = comment ]; then
    case $ext in sh|py|ts|js) ;; *) die usage "comment mode needs --ext sh|py|ts|js" ;; esac
  fi
  [ "$digest" = 1 ] || [ -n "$input" ] || die usage "input file or - is required"
}

resolve_rules() {
  if [ -z "$rules" ]; then
    [ -x "$resolver" ] || [ -f "$resolver" ] || die resolver_missing "$resolver"
    rules=$( (cd "$cwd" && bash "$resolver" prose) 2>/dev/null | jq -r '.prose // empty' ) || rules=
    [ -n "$rules" ] || die rules_unresolved "no prose.md found from $cwd"
  fi
  [ -f "$rules" ] && [ -r "$rules" ] || die rules_unreadable "$rules"
}

load_rules() {
  local l k v h
  # The prose-lint block: "key: value" lines between a ```prose-lint fence and the next fence.
  rules_block=false
  r_hard= r_cap_i=20 r_cap_d=25 r_long=150 r_replace= r_banned=
  # The awk pass decides whether a block exists, so one fence pattern covers the parser and the flag.
  awk -v flag="$work/found" '/^```prose-lint[ \t]*$/ {inb=1; print "" > flag; next} inb && /^```/ {exit} inb' "$rules" > "$work/block"
  if [ -f "$work/found" ]; then
    rules_block=true
    while IFS= read -r l; do
      [ -n "${l//[[:space:]]/}" ] || continue
      k=${l%%:*}; v=${l#*:}; v=${v# }
      case $k in
        hard) r_hard=$v ;;
        cap_instruction) r_cap_i=$v ;;
        cap_descriptive) r_cap_d=$v ;;
        long_reply_words) r_long=$v ;;
        replace) r_replace=$v ;;
        banned) r_banned=$v ;;
        *) die rules_invalid "unknown key in the prose-lint block: $k" ;;
      esac
    done < "$work/block"
  fi
  [ "$rules_block" = true ] || r_hard=$hard_names
  case $r_cap_i$r_cap_d$r_long in *[!0-9]*) die rules_invalid "caps and long_reply_words must be numbers" ;; esac
  for h in $r_hard; do
    case " $hard_names " in *" $h "*) ;; *) die rules_invalid "unknown hard marker: $h" ;; esac
  done
}

print_digest() {
  local d names h
  d=$(awk '
    /^#+[ \t]/ {
      match($0, /^#+/); lvl = RLENGTH
      if (on && lvl <= on) exit
      if (!on && $0 ~ /^#+[ \t]+Self-lint[ \t]*$/) { on = lvl; next }
    }
    on { print }' "$rules" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | sed '/./,$!d')
  if [ -n "$d" ]; then printf '%s\n' "$d"; return 0; fi
  names=
  for h in $r_hard; do names="$names, $(printf '%s' "$h" | tr '_' ' ')"; done
  printf 'Hard markers in force: %s.\n' "${names#, }"
}

read_input() {
  raw=$work/raw
  if [ "$input" = - ]; then cat > "$raw"; else [ -f "$input" ] && [ -r "$input" ] || die input_unreadable "$input"; cat "$input" > "$raw"; fi
}

strip_nonprose() {
  # The stripped copy keeps every line number: removed text becomes an empty line.
  stripped=$work/stripped
  case $filt in
    raw) cp "$raw" "$stripped" ;;
    prose)
      awk '
        /^[ \t]*(```|~~~)/ { fence = !fence; print ""; next }
        fence { print ""; next }
        /^[ \t]*>/ { print ""; next }
        { gsub(/`[^`]*`/, ""); print }' "$raw" > "$stripped" ;;
    comment)
      # A "#" in ts and js starts a private field, so only "//" marks a comment there.
      case $ext in ts|js) lead='^[ \t]*//' ;; *) lead='^[ \t]*#' ;; esac
      awk -v lead="$lead" '
        NR == 1 && /^#!/ { print ""; next }
        $0 ~ lead { gsub(/`[^`]*`/, ""); print; next }
        { print "" }' "$raw" > "$stripped" ;;
  esac

  # An HTML entity (&name; or &#123; or &#x1F;) is not a semicolon: the entity loses its closing mark here.
  # A name needs two or more characters, so AT&T; and R&D; keep their semicolons.
  sed -E 's/(&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+));/\1/g' "$stripped" > "$work/entities" && mv "$work/entities" "$stripped"
}

# emit <marker> <label|-> <grep args...>: one finding row per match. The label replaces the matched text.
emit() {
  local marker=$1 label=$2; shift 2
  { grep -n -o "$@" "$stripped" 2>/dev/null || true; } | awk -v m="$marker" -v lab="$label" '
    { line = $0; sub(/:.*/, "", line); txt = substr($0, length(line) + 2)
      if (lab != "-") txt = lab
      else if (m == "contraction") { sub(/^[^A-Za-z]/, "", txt); sub(/[^A-Za-z]$/, "", txt) }
      printf "%s\t%s\t%s\n", line, m, txt }' >> "$findings"
}

find_markers() {
  local pair from to w
  apos=$'(\'|\xE2\x80\x99)'
  emit em_dash - -F $'\xE2\x80\x94'
  emit semicolon - -F ';'
  emit contraction - -E -i "[A-Za-z]n${apos}t([^A-Za-z]|\$)|[A-Za-z]${apos}(re|ve|ll|m|d)([^A-Za-z]|\$)"
  # The 's forms use -w so the boundary is not consumed and adjacent forms count separately.
  emit contraction - -E -i -w "(it|that|let|there|here|what|who)${apos}s"

  if [ "$soft" = 1 ]; then
    for pair in $r_replace; do
      from=${pair%%>*}; to=${pair#*>}
      from=$(printf '%s' "$from" | tr '_' ' ' | tr -cd 'A-Za-z -')
      [ -n "$from" ] || continue
      emit replace "$from -> $(printf '%s' "$to" | tr '_' ' ')" -E -i "(^|[^A-Za-z])${from}([^A-Za-z]|\$)"
    done
    for w in $r_banned; do
      w=$(printf '%s' "$w" | tr '_' ' ' | tr -cd 'A-Za-z -')
      [ -n "$w" ] || continue
      emit banned "$w" -E -i "(^|[^A-Za-z])${w}([^A-Za-z]|\$)"
    done
  fi
}

find_long_sentences() {
  # A sentence in a numbered list item uses the instruction cap. Every other sentence uses the descriptive cap.
  if [ "$caps" = 1 ] && [ "$rules_block" = true ]; then
    awk -v ci="$r_cap_i" -v cd="$r_cap_d" '
      function flush() { if (n > cap) printf "%d\tlong_sentence\t%d words, cap %d\n", sl, n, cap; n = 0 }
      /^[ \t]*$/ || /^#+[ \t]/ || /^[ \t]*\|/ { flush(); cap = cd; next }
      {
        line = $0
        if (line ~ /^[ \t]*[0-9]+\.[ \t]+/) { flush(); cap = ci; sub(/^[ \t]*[0-9]+\.[ \t]+/, "", line) }
        else if (line ~ /^[ \t]*[-*+][ \t]+/) { flush(); cap = cd; sub(/^[ \t]*[-*+][ \t]+/, "", line) }
        else if (!cap) cap = cd
        nf = split(line, tok, /[ \t]+/)
        for (i = 1; i <= nf; i++) {
          if (tok[i] == "") continue
          if (n == 0) sl = NR
          n++
          if (tok[i] ~ /[.!?]["\x27)\]]*$/) flush()
        }
      }
      END { flush() }' "$stripped" >> "$findings"
  fi
}

count() { awk -F'\t' -v m="$1" '$2 == m {n++} END {print n + 0}' "$findings"; }

count_findings() {
  c_repl=$(count replace) c_ban=$(count banned) c_long=$(count long_sentence)
  words=$(wc -w < "$stripped" | tr -d ' ')

  long_reply=false
  if [ "$longreply" = 1 ] && [ "$words" -gt "$r_long" ] \
    && ! grep -q -E '^[ \t]*(```|~~~)' "$raw" && ! grep -q -E '^[ \t]*\|.*\|' "$raw"; then
    long_reply=true
  fi
}

plural() { if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }
# hard_label <name>: the count of one hard marker with its singular or plural label.
hard_label() {
  local row one many
  row=$(printf '%s\n' "$hard_table" | grep "^$1|")
  one=${row#*|}; many=${one#*|}; one=${one%%|*}
  plural "$(count "$1")" "$one" "$many"
}

build_summaries() {
  local parts p h
  parts=()
  for h in $hard_names; do
    [ "$(count "$h")" -eq 0 ] || parts+=("$(hard_label "$h")")
  done
  [ "$c_repl" -eq 0 ] || parts+=("$(plural "$c_repl" "replaceable word" "replaceable words")")
  [ "$c_ban" -eq 0 ] || parts+=("$(plural "$c_ban" "banned word" "banned words")")
  [ "$c_long" -eq 0 ] || parts+=("$(plural "$c_long" "long sentence" "long sentences")")
  parts+=("$words words")
  summary=
  for p in "${parts[@]}"; do summary="$summary, $p"; done
  summary=${summary#, }

  # The hard summary lists only the markers that are in the hard list and have a count above zero.
  hard_hit=0 hard_summary=
  for h in $r_hard; do
    [ "$(count "$h")" -eq 0 ] || { hard_hit=1; hard_summary="$hard_summary, $(hard_label "$h")"; }
  done
  hard_summary=${hard_summary#, }
}

print_report() {
  if [ "$format" = json ]; then
    hard_json=$(for h in $hard_names; do printf '%s\t%s\n' "$h" "$(count "$h")"; done \
      | jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add')
    jq -cn --argjson h "$hard_json" \
      --argjson r "$c_repl" --argjson b "$c_ban" --argjson l "$c_long" \
      --argjson w "$words" --argjson lr "$long_reply" --argjson rb "$rules_block" --arg sum "$summary" --arg hs "$hard_summary" \
      '{hard:$h, soft:{replace:$r, banned:$b, long_sentence:$l},
        words:$w, long_reply:$lr, rules_block:$rb, summary:$sum, hard_summary:$hs}'
  else
    sort -n -s -t "$(printf '\t')" -k1,1 "$findings" | awk -F'\t' '{ printf "%s: %s: %s\n", $1, $2, $3 }'
  fi
}

main() {
  if [ "${1:-}" = "--selftest" ]; then
    command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"
    selftest
    exit $?
  fi
  if [ "${1:-}" = "--classify" ]; then
    [ $# -eq 2 ] || die usage "--classify needs one path"
    case $2 in
      *.md|*.markdown|*.txt) echo file ;;
      *.sh) echo comment sh ;;
      *.py) echo comment py ;;
      *.ts) echo comment ts ;;
      *.js) echo comment js ;;
      *) exit 1 ;;
    esac
    exit 0
  fi
  command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"
  hard_names=$(printf '%s\n' "$hard_table" | cut -d'|' -f1 | tr '\n' ' ')
  hard_names=${hard_names% }
  parse_args "$@"
  check_options
  resolve_rules

  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  load_rules
  if [ "$digest" = 1 ]; then print_digest; exit 0; fi
  read_input
  strip_nonprose
  findings=$work/findings
  : > "$findings"
  find_markers
  find_long_sentences
  count_findings
  build_summaries
  print_report
  exit "$hard_hit"
}

main "$@"
