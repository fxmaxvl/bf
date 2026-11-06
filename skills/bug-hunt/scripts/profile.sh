#!/usr/bin/env bash
# Profile a hunt scope: size, file kinds, per-lens signal counts and the bug classes no lens owns.
#
# Usage: HUNT_LENSES="<id> <id>..." profile.sh [diff_file]
#   HUNT_LENSES: the lens ids, space separated. hunt-init.sh owns the list. Every id except logic needs a
#          "lens" row in signals(), else the script fails with no_signal.
#   stdin: newline-separated repo-relative paths. Cwd is the repo root. Paths that are not regular
#          files (deleted in the diff) are dropped before anything is counted.
#   diff_file: optional unified diff. It only feeds lines_changed.
#
# Output keys: lines_changed ({added, removed}, or null without a readable diff), scanned (files of kind
#   code or config: the only files grepped for the unowned classes, and the denominator of the suggestion
#   rule; the lens counts also grep test and skill files),
#   modules (distinct first path segments, a root-level file counts as "."), file_kinds (code, test, docs,
#   skill, config, style, other), lenses (one count per HUNT_LENSES id), unowned (one count per bug class no
#   lens owns), suggestions (unowned classes with count >= 1 and count * 10 >= scanned, table order).
#   Every count is a number of files with at least one matching line. lenses.logic is the number of code,
#   test and skill files. lenses.contracts is at least 1 when the scope spans 2 or more modules.
# Errors: {"error":"<code>","detail":"..."} on stdout, exit 1.
set -uo pipefail

if [ "${1:-}" = -h ] || [ "${1:-}" = --help ]; then
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0
fi
command -v jq >/dev/null || { printf '{"error":"no_jq","detail":"jq is required"}\n'; exit 1; }

[ -n "${HUNT_LENSES:-}" ] || { printf '{"error":"no_lenses","detail":"set HUNT_LENSES to the lens id list"}\n'; exit 1; }
diff_file="${1:-}"
existing=$(while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)

# Prompt-like files (SKILL.md, conventions, agents) are kind skill. They are grepped for lens signals
# but not for bug classes. The flow lens hunts them.
# Docs, style and other files are not grepped: a README that says "cache" is not a cache.
kinds=""
[ -z "$existing" ] || kinds=$(jq -R -r '
  def base: split("/") | last;
  def dirs: split("/")[:-1];
  def ext: (base | ascii_downcase) as $b | if ($b | contains(".")) then "." + ($b | split(".") | last) else "" end;
  . as $p
  | (if (base == "SKILL.md") or (ext == ".md" and (dirs | any(. == "conventions" or . == "agents"))) then "skill"
     elif (dirs | any(. == "test" or . == "tests" or . == "__tests__" or . == "spec" or . == "it"))
       or (base | test("\\.test\\.|\\.spec\\.|_test\\.|-smoke\\.|_spec\\.")) then "test"
     elif ext | IN(".css", ".scss", ".sass", ".less") then "style"
     elif ext | IN(".md", ".mdx", ".txt", ".rst", ".adoc") then "docs"
     elif (ext | IN(".json", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".conf", ".xml", ".lock", ".bazel"))
       or (base | IN("Dockerfile", "BUILD")) then "config"
     elif ext | IN(".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".py", ".rb", ".go", ".rs", ".java", ".kt", ".scala",
                   ".sh", ".bash", ".zsh", ".php", ".cs", ".c", ".h", ".cpp", ".swift", ".sql", ".lua") then "code"
     else "other" end) as $k
  | "\($p)\t\($k)"' <<< "$existing")

scan_list=$(printf '%s\n' "$kinds" | awk -F '\t' '$2 == "code" || $2 == "test" || $2 == "skill" || $2 == "config" { print $1 }')
class_list=$(printf '%s\n' "$kinds" | awk -F '\t' '$2 == "code" || $2 == "config" { print $1 }')
scanned=$(printf '%s\n' "$class_list" | grep -c . || true)

file_kinds=$(jq -R -s '
  split("\n") | map(select(length > 0) | split("\t")[1]) as $ks
  | ["code","test","docs","skill","config","style","other"] | map(. as $k | {key: $k, value: ($ks | map(select(. == $k)) | length)}) | from_entries' <<< "$kinds")
modules=$(jq -R -s '
  split("\n") | map(select(length > 0) | split("\t")[0] | if contains("/") then split("/")[0] else "." end) | unique | length' <<< "$kinds")

# One row per signal: group id regex. POSIX ERE matched case-insensitively. A word boundary is spelled
# (^|[^[:alnum:]_])...([^[:alnum:]_]|$) because BSD grep has no \b. Fields split on whitespace, so a
# regex must use [[:space:]] and never a literal space. The unowned rows own the bug-class ids; the smoke
# check keeps the SKILL.md class table equal to them.
signals() {
  cat <<'SIGNALS'
lens errors (^|[^[:alnum:]_])(try|catch|except|finally|rescue|throw|raise|retry|retries)([^[:alnum:]_]|$)|err[[:space:]]*!=[[:space:]]*nil|[|][|][[:space:]]*true|2>/dev/null
lens concurrency (^|[^[:alnum:]_])(async|await|promise|thread|mutex|goroutine|go[[:space:]]+func|settimeout|setinterval|future|executor|synchronized|atomic|semaphore)([^[:alnum:]_]|$)
lens data insert[[:space:]]+into|delete[[:space:]]+from|create[[:space:]]+table|alter[[:space:]]+table|select[[:space:]].*[[:space:]]from[[:space:]]|(^|[^[:alnum:]_])(migration|migrate|schema|transaction|serialize|deserialize)([^[:alnum:]_]|$)|json\.(parse|loads)
lens security (^|[^[:alnum:]_])(eval|innerhtml|dangerouslysetinnerhtml|subprocess|child_process|password|passwd|secret|jwt|csrf|cookie)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])(exec|system)[[:space:]]*\(|shell[[:space:]]*=[[:space:]]*true|api[_-]?key|(^|[^[:alnum:]_])(authoriz|authenticat)
lens contracts ^[[:space:]]*(export|public|interface|def|func|fn|rpc)([^[:alnum:]_]|$)|^[[:space:]]*message[[:space:]]+[a-z]|module\.exports|^#[[:space:]]*(usage|output keys?|contract):
lens flow ^#{1,4}[[:space:]]+(phase|step)[[:space:]]+[0-9]|(^|[^[:alnum:]_])(main|handler|router|pipeline)[[:space:]]*\(
unowned resource-leak (^|[^[:alnum:]_])(fopen|createreadstream|createwritestream|addeventlistener|createpool|getconnection)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])new[[:space:]]+(web)?socket|net\.connect|os\.open
unowned time date\.now|(^|[^[:alnum:]_])new[[:space:]]+date|(^|[^[:alnum:]_])(datetime|timezone|tzinfo|toisostring|gettimezoneoffset|dayjs|strftime|strptime|localdate|zoneddatetime|utc)([^[:alnum:]_]|$)|tz=|moment\(|time\.time
unowned numeric-precision (^|[^[:alnum:]_])(parsefloat|tofixed|bigdecimal|bigint)([^[:alnum:]_]|$)|math\.(round|floor|ceil)|(^|[^[:alnum:]_])(decimal|float|round)[[:space:]]*\(
unowned cache-invalidation (^|[^[:alnum:]_])(cache|memoize|ttl|evict|lru|redis)([^[:alnum:]_]|$)|memo\(|invalidat
SIGNALS
}

for id in $HUNT_LENSES; do
  [ "$id" = logic ] || signals | grep -q "^lens $id " ||
    { printf '{"error":"no_signal","detail":"lens %s has no signal row"}\n' "$id"; exit 1; }
done

counts=$(signals | while read -r group id re; do
  list=$scan_list; [ "$group" = unowned ] && list=$class_list
  n=$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 grep -lIiE -e "$re" -- /dev/null 2>/dev/null | grep -c . || true)
  printf '%s\t%s\t%s\n' "$group" "$id" "$n"
done)

lines_changed=null
if [ -n "$diff_file" ] && [ -r "$diff_file" ]; then
  # Only lines after an @@ header are content; the ---/+++ file headers come before it.
  read -r added removed < <(awk '/^diff /{h=0} /^@@/{h=1; next} h && /^\+/{a++} h && /^-/{r++} END{print a+0, r+0}' "$diff_file")
  lines_changed=$(jq -nc --argjson a "$added" --argjson r "$removed" '{added: $a, removed: $r}')
fi

jq -nc --arg ids "$HUNT_LENSES" --argjson lines "$lines_changed" --argjson scanned "$scanned" --argjson modules "$modules" \
  --argjson kinds "$file_kinds" --arg counts "$counts" '
  ($counts | split("\n") | map(select(length > 0) | split("\t"))) as $rows
  | ([$rows[] | select(.[0] == "lens") | {key: .[1], value: (.[2] | tonumber)}] | from_entries) as $lens
  | ([$rows[] | select(.[0] == "unowned") | {key: .[1], value: (.[2] | tonumber)}] | from_entries) as $unowned
  | {lines_changed: $lines, scanned: $scanned, modules: $modules, file_kinds: $kinds,
     lenses: (({logic: ($kinds.code + $kinds.test + $kinds.skill)} + $lens
               | if $modules >= 2 and (.contracts // 1) < 1 then .contracts = 1 else . end) as $all
              | [$ids | split(" ")[] | select(length > 0) | {key: ., value: $all[.]}] | from_entries),
     unowned: $unowned,
     suggestions: [$rows[] | select(.[0] == "unowned") | select((.[2] | tonumber) >= 1 and (.[2] | tonumber) * 10 >= $scanned) | .[1]]}'
