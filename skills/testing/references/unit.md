# Unit Tests

One unit, one process, no I/O. Assertion discipline, structure, doubles, and determinism that apply
everywhere are in `test-quality.md`; this file covers what's specific to this level.

## Contents

- [What makes it a unit test](#what-makes-it-a-unit-test)
- [Discovering a project's conventions](#discovering-a-projects-conventions)
- [Parameterized and property-based tests](#parameterized-and-property-based-tests)
- [Per-ecosystem notes](#per-ecosystem-notes)
- [Sources](#sources)

## What makes it a unit test

Solitary and sociable tests are both unit tests. Replacing every collaborator with a double
(solitary) versus letting the unit call real collaborators that are fast and deterministic
(sociable) is a style choice. What makes a test an integration test instead is a real
*out-of-process* collaborator — a socket, a file, a container, a live clock-driven service. A unit
test with every collaborator doubled belongs here regardless of which directory it sits in.

## Discovering a project's conventions

Before writing anything:

1. Read the runner configuration — it names the test paths, discovery pattern, and command.
2. Read a few existing tests in the area being changed. Match their file layout, naming, assertion
   style, and setup idiom even where it differs from the defaults below — a consistent suite beats a
   correct-but-foreign test.
3. Inventory existing helpers — factories, builders, fixtures, custom matchers — and reuse them. A
   duplicate helper is a defect, not a convenience.
4. Find the command that runs a single file, not just the whole suite; it gets run many times over
   the course of the work.

## Parameterized and property-based tests

Parameterized tests replace loops: one test body, a table of cases, one reported result per case
with a name that identifies it. Use the framework's native support rather than iterating inside a
test body.

Property-based testing (Hypothesis, fast-check, QuickCheck-style tools) generates inputs and shrinks
failures to a minimal counterexample. It complements example-based tests rather than replacing them —
examples pin the behaviors that were deliberately decided, properties hunt edges nobody thought of.
Good candidates: round-trips (encode/decode), invariants (a result always within bounds), and
equivalence against a simpler reference implementation.

## Per-ecosystem notes

Durable, non-obvious conventions worth knowing before writing into an unfamiliar codebase. Always
defer to what the project's own config and existing tests actually do.

**JavaScript / TypeScript.** Mock cleanup is off by default in Jest and Vitest (`clearMocks`,
`resetMocks`, `restoreMocks` all default `false`), which is a common source of cross-test leakage —
enable `restoreMocks` or restore explicitly rather than trusting tests to clean up after each other.
Module mocking (`vi.mock`/`jest.mock`) replaces exports for *external* importers only — calls made
from inside the mocked module still hit the original, so a test that needs internals mocked is a
sign the module does too much. For network calls, intercept at the network layer (a request-handler
library) rather than stubbing the HTTP client, so the handlers are reusable across levels. For
DOM/component tests, query by role and accessible name rather than class or DOM structure.

**Python.** pytest discovers `test_*.py` / `*_test.py`, functions prefixed `test`, classes prefixed
`Test`. Shared setup lives in `conftest.py` at the narrowest scope that works — `function` by
default; `module`/`session` only for genuinely immutable, expensive setup, since a session-scoped
mutable fixture is a cross-test-pollution bug waiting to happen. Prefer `@pytest.mark.parametrize`
with `ids=` for readable case names over a loop. `unittest.mock` with `autospec=True` rejects calls
the real object would reject; `monkeypatch` handles environment and attributes with automatic undo.

**Java / Kotlin.** Test file naming has to match the runner's discovery pattern to be collected at
all (Maven Surefire defaults to `Test*.java`, `*Test.java`, `*Tests.java`, `*TestCase.java`).
`@ParameterizedTest` with a `name` attribute for readable case labels; AssertJ or Truth over bare
`assertEquals` for failure messages that localize the defect. `@SpringBootTest` loads the whole
application context and belongs at the integration level, not here, even when it's discovered by the
unit runner.

**Go.** Table-driven tests are the idiom: a slice or map of case structs, one `t.Run(name, ...)` per
case so failures name the case. `t.Helper()` so failures point at the caller; `t.Cleanup(fn)` over
`defer` for teardown. Small interfaces defined at the consumer, satisfied by a hand-written fake, are
usually enough — a generated mock that asserts call sequences is the standard route to a
change-detector test in this ecosystem.

**.NET.** A separate `*.Tests` project per production project keeps test-only dependencies out of the
production build. `MethodName_Scenario_ExpectedBehavior` naming; prefer helper factory methods over
`Setup`/`TearDown` attributes so everything a test depends on stays visible in the test body.

**Ruby.** RSpec: `describe` the unit, `context` the scenario, `it` the expected behavior; prefer
`let`/`let!` over instance variables in `before`. Run with `--order random` — a suite that only
passes in declaration order has inter-test dependencies. Verifying doubles (`instance_double`,
`class_double`) over bare `double`, so a double rejects methods the real class doesn't have.

## Sources

- Jest configuration defaults — https://jestjs.io/docs/configuration
- Vitest mocking guide — https://vitest.dev/guide/mocking
- pytest good practices and parametrize — https://docs.pytest.org/en/stable/explanation/goodpractices.html
- JUnit 5 user guide — https://docs.junit.org/current/user-guide/
- Go table-driven tests — https://go.dev/wiki/TableDrivenTests
- Microsoft Learn, *Best practices for writing unit tests* — https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices
- RSpec documentation — https://rspec.info/documentation/
- Hypothesis, property-based testing — https://hypothesis.readthedocs.io/
