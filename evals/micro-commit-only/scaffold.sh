#!/usr/bin/env bash
set -euo pipefail
origin=$(mktemp -d)/origin.git
git init -q --bare "$origin"
git init -q -b main
git remote add origin "$origin"
mkdir -p src
printf '#!/usr/bin/env bash\nn=$1\necho "hello $n"\n' > src/greet.sh
git add src/greet.sh
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
git push -q -u origin main
