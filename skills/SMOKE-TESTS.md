# Smoke tests

Maintainer reference, not a skill. Run the matching smoke script after changing a script it covers;
each prints one PASS/FAIL line per case and exits non-zero on any failure. Run them with macOS
`/bin/bash` (3.2) first on PATH as well, since that is what many users have.

| Smoke script | Covers |
|---|---|
| `skills/feature/scripts/added-todos-smoke.sh` | `added-todos.sh` |
| `skills/scan-conventions/scripts/resolve-conventions-smoke.sh` | `resolve-conventions.sh`, `convention-tiers.sh`, `discover-conventions.sh` |
