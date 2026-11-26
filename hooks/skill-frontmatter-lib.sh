# Shared reader of the SKILL.md frontmatter. Source it; it sets no trap and no option.
# skill_frontmatter <file>: prints the lines between the first two --- lines, when the first line is ---.
skill_frontmatter() {
  awk 'NR==1 && $0=="---"{inf=1;next} inf && $0=="---"{exit} inf{print}' "$1"
}
