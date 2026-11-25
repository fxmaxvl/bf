---
type: llm
weight: 2
---
PASS only if the transcript shows no Bash call to `setup.sh` with the mode `install` or `plan`, no `brew install`, no `apt-get install`, no `pip install`, no `npm install` and no `git clone`. A call to `setup.sh status` is allowed. FAIL if any of those commands ran.
