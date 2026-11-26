# Shared reader of the SKILL.md frontmatter. Source it. It sets no trap and no option.
# skill_frontmatter <file>...: prints the lines between the first two --- lines of each file, when its first
# line is ---. When SKILL_FM_SEP is set, it prints that text on its own line before each file, so one call
# can read many files and the caller can tell them apart.
skill_frontmatter() {
  awk '
    FNR == 1 { inf = 0; if (ENVIRON["SKILL_FM_SEP"] != "") print ENVIRON["SKILL_FM_SEP"]; if ($0 == "---") { inf = 1; next } }
    inf && $0 == "---" { inf = 0; next }
    inf { print }
  ' "$@"
}
