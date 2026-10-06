#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
mkdir -p db/migrations .github/workflows .eval-home
printf '# Fixture Shop\n\nA small shop: a cart service and a payments service behind one API.\n' > README.md
printf '.eval-home/\n' > .gitignore
printf 'CREATE TABLE orders (id INTEGER PRIMARY KEY, total INTEGER NOT NULL);\n' > db/migrations/001_init.sql
printf 'CREATE TABLE payments (id INTEGER PRIMARY KEY, order_id INTEGER NOT NULL);\n' > db/migrations/002_payments.sql
printf 'name: ci\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: npm test --workspaces\n' > .github/workflows/ci.yml
printf '{"name":"fixture-shop","private":true,"workspaces":["services/*"]}\n' > package.json

# Two build units and enough tracked files (>= 50) that the survey and lesson writers fan out.
for svc in cart payments; do
  d=services/$svc
  mkdir -p "$d/src" "$d/test"
  printf '{"name":"%s","scripts":{"test":"node --test"}}\n' "$svc" > "$d/package.json"
  printf '# %s service\n' "$svc" > "$d/README.md"
  for i in $(seq 1 12); do
    printf 'exports.step%s = (x) => x + %s;\n' "$i" "$i" > "$d/src/step$i.js"
    printf 'const test = require("node:test");\ntest("step%s", () => {});\n' "$i" > "$d/test/step$i.test.js"
  done
done

git add -A
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
