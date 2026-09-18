#!/usr/bin/env bash
# Static audit of this plugin's own skills, scripts, conventions, and README.
#
# Every check here is mechanical -- path existence, frontmatter fields, grep
# hits, shell syntax. They run once and hand the model a compact finding list,
# so no invocation spends tokens re-deriving what a grep can settle.
#
# Usage: audit-static.sh [--root <plugin-repo-root>]
#   --root  default: git rev-parse --show-toplevel
#
# Output (stdout, single JSON object):
#   {root, counts:{skills,scripts,findings}, findings[], notes[]}
#     findings[] = {audit_id, check, severity, path, line, detail, axes[]}
#       audit_id: "<check>:<path>[:<symbol>]" -- stable fingerprint; the model
#                 writes it into the filed issue so later runs dedupe on it
# Errors: {"error":"<code>","detail":"..."} + exit 1
set -uo pipefail

die() { printf '{"error":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 1; }
command -v jq >/dev/null 2>&1 || die jq_missing "jq not installed"

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 || die bad_args "--root needs a value" ;;
    *) die bad_args "unknown argument: $1" ;;
  esac
done
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die no_repo "not a git repo; pass --root"
[ -d "$ROOT/skills" ] || die not_plugin_repo "no skills/ under $ROOT -- this is not the plugin repo"

TMP=$(mktemp) || die mktemp_failed ""
trap 'rm -f "$TMP"' EXIT

emit_id() { # audit_id check severity path line detail axes_csv
  jq -cn --arg i "$1" --arg c "$2" --arg s "$3" --arg p "$4" --arg l "$5" --arg d "$6" --arg a "$7" \
    '{audit_id:$i, check:$c, severity:$s, path:$p,
      line:(if $l=="" then null else ($l|tonumber) end), detail:$d,
      axes:($a|split(",")|map(select(length>0)))}' >>"$TMP"
}

README="$ROOT/README.md"
N_SKILLS=0; N_SCRIPTS=0

# ---- per-skill checks -------------------------------------------------------
while IFS= read -r skill; do
  N_SKILLS=$((N_SKILLS+1))
  rel="skills/$skill/SKILL.md"
  f="$ROOT/$rel"

  fm=$(awk 'NR==1 && $0=="---"{inf=1;next} inf && $0=="---"{exit} inf{print}' "$f")
  for field in name description model allowed-tools; do
    printf '%s\n' "$fm" | grep -q "^$field:" && continue
    # name/description/model gate discovery and dispatch; allowed-tools is drift
    case "$field" in name|description|model) sev=high ;; *) sev=medium ;; esac
    emit_id "missing-frontmatter-field:$rel:$field" missing-frontmatter-field "$sev" "$rel" "" \
      "frontmatter is missing required field \`$field:\`" "code-quality"
  done

  fm_name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
  [ "$fm_name" = "$skill" ] || emit_id "name-mismatch:$rel" name-mismatch high "$rel" "" \
      "frontmatter name \`$fm_name\` does not match directory \`$skill\`" "code-quality"

  # plugin-main.md must be read before anything else runs
  first=$(awk 'NR==1 && $0=="---"{inf=1;next} inf && $0=="---"{inf=0;seen=1;next} seen && NF{print;exit}' "$f")
  case "$first" in
    *"conventions/plugin-main.md"*) ;;
    *) emit_id "missing-plugin-main:$rel" missing-plugin-main high "$rel" "" \
         "first line after frontmatter does not read \`conventions/plugin-main.md\`; got: ${first:0:70}" "code-quality" ;;
  esac

  # A thin wrapper that only delegates to another SKILL.md owns neither a
  # banner nor failure modes -- the skill it hands off to does. Deliberate
  # heuristic: short, points at another SKILL.md, and runs no phases of its own.
  # A skill with its own `## Phase` headings is never exempt, however short.
  wrapper=false
  if [ "$(wc -l <"$f")" -lt 25 ] && grep -q 'SKILL\.md' "$f" && ! grep -q '^## Phase' "$f"; then
    wrapper=true
  fi

  if [ "$wrapper" = false ]; then
    grep -q '──' "$f" || emit_id "missing-banner:$rel" missing-banner medium "$rel" "" \
        "no \`──\` status banner -- the skill starts work with no visible signal it is running" "code-quality"

    grep -qiE '^## (Edge Cases|Error)' "$f" || emit_id "missing-edge-cases:$rel" missing-edge-cases low "$rel" "" \
        "no \`## Edge Cases\` or \`## Error\` section -- failure modes are undocumented" "code-quality"
  fi

  # Path literals that break on anyone else's machine. The fingerprint uses the
  # matched literal, never the line number -- a line number shifts on every
  # unrelated edit and the finding would re-file as new.
  while IFS=: read -r ln hit; do
    [ -n "$hit" ] || continue
    emit_id "hardcoded-path:$rel:$hit" hardcoded-path high "$rel" "$ln" \
      "absolute local path \`$hit\` instead of \`\${CLAUDE_PLUGIN_ROOT}\` -- breaks on any other machine or plugin version" "code-quality"
  done < <(grep -n -o -E '/(Users|home)/[a-zA-Z0-9._-]+/|/plugins/cache/' "$f" 2>/dev/null | sort -u -t: -k2)

  # README must advertise the skill
  grep -q "\`/bf:$skill" "$README" 2>/dev/null \
    || emit_id "missing-readme-row:$rel" missing-readme-row medium "$rel" "" \
         "no row for \`/bf:$skill\` in README's \`What's inside\` table -- the skill is undiscoverable" "code-quality"
done < <(cd "$ROOT/skills" && for d in */; do [ -f "${d}SKILL.md" ] && printf '%s\n' "${d%/}"; done)

# ---- reference integrity (every SKILL.md, including nested sub-skills) ------
while IFS= read -r f; do
  rel=${f#"$ROOT/"}
  # ${CLAUDE_PLUGIN_ROOT}/... references
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    [ -e "$ROOT/$ref" ] || emit_id "broken-ref:$rel:$ref" broken-ref high "$rel" "" \
      "references \`\${CLAUDE_PLUGIN_ROOT}/$ref\` which does not exist" "code-quality"
  done < <(grep -o '\${CLAUDE_PLUGIN_ROOT}/[A-Za-z0-9._/-]*' "$f" 2>/dev/null \
           | sed 's|\${CLAUDE_PLUGIN_ROOT}/||' | sed 's|[./]*$||' | sort -u)
  # bare sub-skill references like `feature/verify/SKILL.md`. Documentation
  # placeholders (`path/to/SKILL.md`) are exempted by their leading segment --
  # anything else missing is flagged, including a ref to a skill that never
  # existed, which is the breakage most worth catching.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    ref=${ref#skills/}
    case "${ref%%/*}" in path|to|name|example|foo|bar|your|my) continue ;; esac
    [ -e "$ROOT/skills/$ref" ] || emit_id "broken-subskill-ref:$rel:$ref" broken-subskill-ref high "$rel" "" \
      "references sub-skill \`$ref\` which does not exist under \`skills/\`" "code-quality"
  done < <(grep -v 'CLAUDE_PLUGIN_ROOT' "$f" 2>/dev/null \
           | grep -o -E '[a-z0-9][a-z0-9-]*(/[a-z0-9-]+)+/SKILL\.md' | sort -u)
done < <(find "$ROOT/skills" -name SKILL.md -type f | sort)

# ---- scripts ---------------------------------------------------------------
while IFS= read -r s; do
  N_SCRIPTS=$((N_SCRIPTS+1))
  rel=${s#"$ROOT/"}
  bash -n "$s" 2>/dev/null || emit_id "script-syntax:$rel" script-syntax high "$rel" "" \
      "\`bash -n\` fails -- the script cannot run" "code-quality"
  [ -x "$s" ] || emit_id "script-not-executable:$rel" script-not-executable low "$rel" "" \
      "not executable (chmod +x); callers must prefix \`bash\`" "code-quality"
  base=$(basename "$s")
  grep -rqF "$base" --include='*.md' "$ROOT/skills" "$ROOT/conventions" 2>/dev/null \
    || emit_id "orphan-script:$rel" orphan-script medium "$rel" "" \
         "no SKILL.md or convention references \`$base\` -- dead weight, or a skill lost its call" "token-frugality,code-quality"
done < <(find "$ROOT/skills" -path '*/scripts/*.sh' -type f | sort)

# ---- README rows pointing at skills that no longer exist -------------------
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -f "$ROOT/skills/$name/SKILL.md" ] || emit_id "readme-orphan-row:$name" readme-orphan-row medium "README.md" "" \
      "README advertises \`/bf:$name\` but \`skills/$name/SKILL.md\` does not exist" "code-quality"
done < <(grep -o -E '`/bf:[a-z0-9-]+' "$README" 2>/dev/null | sed 's|`/bf:||' | sort -u)

jq -s --arg root "$ROOT" --argjson ns "$N_SKILLS" --argjson nsc "$N_SCRIPTS" \
  '{root:$root, counts:{skills:$ns, scripts:$nsc, findings:length},
    findings:(sort_by(if .severity=="high" then 0 elif .severity=="medium" then 1 else 2 end)),
    notes:["static checks only; token-frugality and convention-drift judgment come from the analysis pass in SKILL.md"]}' "$TMP"
