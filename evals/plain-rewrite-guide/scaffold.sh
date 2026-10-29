#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
mkdir -p docs
cat > docs/GUIDE.md <<'MD'
# Running the order service

Our seamless order service is a robust, battle-tested solution — it leverages Node 20 to facilitate lightning-fast checkout for every customer.

It is important to note that you'll need to ensure the service is started prior to running the tests; otherwise the tests won't be able to connect.

## Start

In order to start the service, run the following command:

```
$ make build; make test
```

The service is initialized on port 8080 and failed requests are retried 3 times by the client.

Additionally, logs are written to `/var/log/orders.log`. Furthermore, the full API reference is available at https://example.com/orders/api.

## Why it matters

This isn't just about speed, it's about genuinely empowering teams to unlock their true potential.
MD
git add -A
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
