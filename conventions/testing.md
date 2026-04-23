# Testing Conventions

- Tests MUST cover the functionality being implemented.
- NEVER ignore the output of the system or the tests - Logs and messages often contain CRITICAL information.
- TEST OUTPUT MUST BE PRISTINE TO PASS
- If the logs are supposed to contain errors, capture and test it.
- NO EXCEPTIONS POLICY: Under no circumstances should you mark any test type as "not applicable". Every project, regardless of size or complexity, MUST have unit tests, integration tests, AND end-to-end tests. If you believe a test type doesn't apply, you need the human to say exactly "I AUTHORIZE YOU TO SKIP WRITING TESTS THIS TIME"

## Test context

All test setup state must be collected into a single context object (e.g. `testCtx`, `ctx`, `TestCtx`). It must be initialized before each test via a dedicated initializer — a factory function, constructor, or equivalent. Setup variables must not be declared individually and scattered across the describe/test scope.

The factory function (e.g. `createTestCtx`) or equivalent initializer MUST be defined at the end of the test file, after all `describe`/`it` blocks.

**Why:** scattered setup variables are easy to forget to reinitialize, which causes state to bleed between tests (safety). A single context object is one place to look for all setup state (readability), and a consistent pattern across suites makes tests easier to navigate and review (uniformity). Placing the factory at the bottom keeps the test logic prominent and the setup details out of the way.

## Unit test isolation

Unit tests MUST be fully isolated from external systems. This means:

- No HTTP/network calls (mock fetch, axios, SDK clients, etc.)
- No file system access beyond temp/in-memory
- No database connections
- No environment-specific dependencies (env vars, secrets, ports)

If your unit test makes a real network call, it is an **integration test**, not a unit test. Name it and place it accordingly.

Use dependency injection, mocks, or stubs to control all I/O at the boundary. The test must pass offline and deterministically every time.
