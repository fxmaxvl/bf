#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
mkdir -p scripts/lib
cat > scripts/lib/strings.sh <<'EOF'
#!/usr/bin/env bash
# String helpers shared by the scripts in this repo.

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}
EOF
git add scripts/lib/strings.sh
git -c user.email=eval@example.com -c user.name=eval commit -q -m "add string helpers"
