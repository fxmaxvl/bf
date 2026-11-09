#!/usr/bin/env bash
set -euo pipefail
origin=$(mktemp -d)/origin.git
git init -q --bare "$origin"
git init -q -b main
git config user.email eval@example.com
git config user.name eval
git config commit.gpgsign false
git remote add origin "$origin"
mkdir -p src
printf '#!/usr/bin/env bash\nn=$1\necho "hello $n"\n' > src/greet.sh
git add src/greet.sh
git commit -q -m init
git push -q -u origin main
