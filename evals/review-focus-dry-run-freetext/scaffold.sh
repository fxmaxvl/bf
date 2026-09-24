#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
mkdir -p src
printf '#!/usr/bin/env bash\necho "hello"\n' > src/app.sh
git add src/app.sh
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
printf '#!/usr/bin/env bash\nname=$1\necho "hello $name"\n' > src/app.sh
