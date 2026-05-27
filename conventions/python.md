# Python Conventions

## Testing

- Follow the test context pattern from `testing.md`. In Python: declare a `TestCtx` dataclass or use a module-level `create_test_ctx` factory that constructs and returns all setup state; call it in a `pytest` fixture scoped to the test function. Place the factory/fixture at the end of the file, after all test classes and functions.

```python
import pytest
from dataclasses import dataclass
from unittest.mock import MagicMock

# --- tests ---

class TestUserService:
    def test_returns_user(self, ctx: "TestCtx") -> None:
        ctx.repo.find.return_value = {"id": 1}
        result = ctx.service.get(1)
        assert result == {"id": 1}

# --- test helpers (end of file) ---

@dataclass
class TestCtx:
    repo: MagicMock
    service: "UserService"

@pytest.fixture
def ctx() -> TestCtx:
    return create_test_ctx()

def create_test_ctx() -> TestCtx:
    repo = MagicMock()
    return TestCtx(repo=repo, service=UserService(repo))
```

- Use `pytest` fixtures and `unittest.mock.MagicMock` (or `pytest-mock`'s `mocker`) for isolation. Prefer `MagicMock` over manual stubs for auto-syncing interface changes.
- Use `tmp_path` (built-in fixture) for any test requiring filesystem access — never write to real paths.
- Use `conftest.py` for shared fixtures; keep test-local helpers in the test file itself.
- `pytest.mark.parametrize` over copy-pasted test functions.

## Type Hints

- `X | None` instead of `Optional[X]` (Python 3.10+).
- No mutable default arguments — use `field(default_factory=...)` in dataclasses, `None` sentinel otherwise.

```python
# wrong
def process(items: list[str] = []) -> None: ...

# right
def process(items: list[str] | None = None) -> None:
    if items is None:
        items = []
```

- No bare `except:` — always name the exception (`except ValueError:`, `except Exception as e:`).
- Prefer `dataclasses.dataclass` over manual `__init__` for data-holding classes.

## Modern Idioms

- `pathlib.Path` over `os.path` for all filesystem operations.
- Context managers (`with`) for any resource that has a close/release operation.
- `async`/`await` for I/O-bound work; do not mix sync blocking calls inside async functions.

## Docstrings

- Docstrings on public API (exported functions, classes, methods). Not on private helpers or internals.
- Keep them short: what it does, what it returns, what it raises. Google-style if the project already uses it; otherwise one-line suffices.
- No docstrings on test functions — the test name should be self-documenting.

## Linting & Tooling

- Before starting, look for the project's config file (`pyproject.toml`, `project.toml`, `setup.cfg`, `setup.py`) and check which tools are configured (`ruff`, `mypy`, `black`, `flake8`).
- If tools are configured, run them and fix all issues before considering the task complete. Do NOT add `# noqa` / `# type: ignore` to make code pass — fix the underlying issue.
- **Greenfield default:** `ruff` (lint + format) + `mypy --strict`. Suggest these when the project has no tooling config yet.
- Use the project's existing `venv`. Activate it before running any tool (`source .venv/bin/activate` or equivalent). Do not create a new venv unless none exists.
