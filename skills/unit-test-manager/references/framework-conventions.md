# Framework Conventions

## Contents

- [Discovering an unfamiliar project](#discovering-an-unfamiliar-project)
- [JavaScript and TypeScript](#javascript-and-typescript)
- [Python](#python)
- [Java and Kotlin](#java-and-kotlin)
- [Go](#go)
- [.NET](#net)
- [Ruby](#ruby)
- [Sources](#sources)

## Discovering an unfamiliar project

Match the project before applying any default below. In order:

1. **Read the runner config** — `package.json`/`vitest.config.*`/`jest.config.*`, `pyproject.toml`
   or `pytest.ini`, `pom.xml`/`build.gradle`, `*.csproj`, `.rspec`. It names the test paths, the
   discovery patterns, and the command.
2. **Read three existing tests** in the area you are changing. Copy their file layout, naming style,
   assertion library, and setup idiom even where it differs from the defaults here. A consistent
   suite beats a correct-but-foreign test.
3. **Inventory the existing helpers** — factories, builders, fixtures, custom matchers, fake
   implementations. Reuse them. A duplicate helper is a defect, not a convenience.
4. **Find the command that runs one file**, not just the whole suite. You will run it many times.
5. **Check CI config** for the real invocation, including the flags that differ from local runs.

## JavaScript and TypeScript

**Jest defaults.** `testMatch` is `["**/__tests__/**/*.?([mc])[jt]s?(x)",
"**/?(*.)+(spec|test).?([mc])[jt]s?(x)"]` — so both a `__tests__/` directory and a
`.test.` / `.spec.` suffix are idiomatic, colocated with source or under a test root.
`testPathIgnorePatterns` defaults to `["/node_modules/"]`.

**Mock cleanup is off by default and this causes cross-test leakage.** `clearMocks`, `resetMocks`,
and `restoreMocks` all default to `false`. `clearMocks` clears call history only; `resetMocks` also
removes implementations; `restoreMocks` additionally restores the original implementation. Enable
`restoreMocks` (or restore explicitly) rather than relying on tests to clean up after each other.

**Vitest** follows the same shape with `vi.fn`, `vi.spyOn`, and `vi.mock`. Its documentation is
explicit: always clear or restore mocks before or after each run, because mocked state — including
`vi.setSystemTime` — does not reset itself. `vi.stubGlobal` and `vi.stubEnv` have matching
`unstubGlobals` / `unstubEnvs` config options.

**`node:test`** ships with Node and needs no dependency: `test()` from `node:test`, assertions from
`node:assert/strict`, subtests via `t.test`, fake timers via `t.mock.timers.enable({ apis:
['setTimeout'] })` and `t.mock.timers.tick(ms)`.

**Parameterized:** `test.each` (Jest, Vitest) or a table plus `for...of` around `test()` — the table
drives the runner, so each case reports separately.

**Module mocking is the most-abused tool in this ecosystem.** `vi.mock`/`jest.mock` on a module
replaces exports for external importers only; calls *inside* the module still hit the original. If a
test needs the internals mocked, the module is doing too much. For network, intercept at the network
layer (Mock Service Worker) rather than stubbing `fetch` or the HTTP client — handlers then describe
server behavior and can be reused across unit, integration, and browser tests.

**DOM/component tests:** query by role and accessible name, not by class or DOM structure. The
Testing Library principle — "the more your tests resemble the way your software is used, the more
confidence they can give you" — argues for user-visible queries, which is compatible with the rule
against asserting copy: query by role and `data-*` id, assert on state and structure, not on the
sentence inside the element.

## Python

**Layout.** pytest recommends tests outside the application code, with a `src/` layout, so tests run
against the installed package rather than a local directory that happens to be importable:

```
pyproject.toml
src/mypkg/
tests/test_app.py
```

**Discovery.** Files `test_*.py` or `*_test.py`; functions prefixed `test`; classes prefixed `Test`
with no `__init__`; `unittest.TestCase` subclasses are also collected. `__init__.py` files in test
directories matter for the legacy prepend/append import modes; the `importlib` import mode avoids
`sys.path` manipulation and the surprises that come with it.

**Fixtures.** Shared setup lives in `conftest.py` at the narrowest scope that works. Scope
deliberately — `function` by default; `module` or `session` only for genuinely immutable, expensive
setup. A session-scoped mutable fixture is a cross-test-pollution bug waiting to happen.

**Parameterized.** `@pytest.mark.parametrize("input,expected", [...])`, stacked decorators for a
Cartesian product, `pytest.param(..., marks=...)` and `ids=` for readable case names. Never a
`for` loop inside a test.

**Doubles.** `unittest.mock` with `autospec=True` or `create_autospec` so the double rejects calls
the real object would reject. `monkeypatch` for environment and attributes, with automatic undo.
`freezegun` or an injected clock for time.

## Java and Kotlin

**Layout.** `src/test/java` mirroring `src/main/java` package for package. Maven Surefire's default
includes are `Test*.java`, `*Test.java`, `*Tests.java`, `*TestCase.java` — unit tests must match one
of these to be discovered at all. Integration tests conventionally end in `*IT.java` and run under
Failsafe in a separate phase.

**JUnit 5.** `@Test` methods; `@DisplayName` for a readable behavior sentence, or
`@DisplayNameGeneration(ReplaceUnderscores.class)` to turn `rejects_withdrawal_when_balance_empty`
into a sentence automatically. `@Nested` inner classes group tests by the state they share, which is
the cleanest way to express given-when-then in Java. `@ParameterizedTest` with `@ValueSource`,
`@CsvSource`, or `@MethodSource`, and a `name` attribute for readable case labels.

**Assertions.** AssertJ or Truth over bare `assertEquals` — the fluent form takes the subject and
produces a failure message that localizes the defect.

**Doubles.** Mockito for stubs and interaction assertions; prefer constructor injection so a real or
fake collaborator can be passed instead. `@SpringBootTest` loads the whole context and belongs in the
integration suite; slice annotations (`@DataJpaTest`, `@WebMvcTest`) are narrower but still not unit
tests.

## Go

**Naming.** Test files end `_test.go` and are excluded from normal builds. Functions are
`TestXxx(*testing.T)` where `Xxx` does not start with a lowercase letter. Benchmarks are
`BenchmarkXxx(*testing.B)`; fuzz targets are `FuzzXxx(*testing.F)`.

**Table-driven tests are the idiom.** A slice or map of case structs, one `t.Run(name, func(t
*testing.T){...})` per case so failures name the case. Map-keyed tables get names for free and
randomize iteration order, which surfaces accidental inter-case dependencies.

**Failure calls.** `t.Errorf` continues the test and reports every failing case; `t.Fatal` stops
when continuing is meaningless. Error messages should print got and want.

**Helpers and cleanup.** `t.Helper()` so failures point at the caller; `t.Cleanup(fn)` runs in
reverse order and replaces defer-based teardown. `t.Parallel()` on parent and subtests to run them
concurrently.

**Doubles.** Small interfaces defined at the consumer, satisfied by a hand-written fake. Go projects
rarely need a mocking framework, and generated mocks that assert call sequences are the standard
route to change-detector tests.

## .NET

**Layout.** A separate `*.Tests` project per production project, referencing it. Keeping the test
project separate from the production project is also what keeps infrastructure packages out of the
unit test build.

**Naming.** `MethodName_Scenario_ExpectedBehavior` — for example `Add_EmptyString_ReturnsZero`.

**Structure.** Arrange–Act–Assert with the act on its own line, assigned to a local, so the assert
does not call the code under test.

**Minimally passing tests.** Use the simplest input that demonstrates the behavior. Extra properties
and non-zero values that the behavior does not depend on make the test brittle and obscure its
intent. Name any value that carries meaning — no magic strings.

**Parameterized.** xUnit `[Theory]` with `[InlineData]`/`[MemberData]`; NUnit `[TestCase]`; MSTest
`[DataRow]`. Prefer these to multiple acts in one test.

**Setup.** Prefer helper factory methods over `Setup`/`TearDown` attributes: everything the test
depends on stays visible inside it, and tests stop sharing state. xUnit removed `SetUp`/`TearDown`
for this reason — constructor and `IDisposable` per test class instead.

**Seams for statics.** Wrap `DateTime.Now`, environment access, and other ambient statics behind an
injected interface, then substitute it. This is the standard fix for a test whose result depends on
the day it runs.

## Ruby

**RSpec.** `spec/` mirroring `app/` or `lib/`, files ending `_spec.rb`. `describe` the unit,
`context` the scenario ("when the balance is empty"), `it` the expected behavior. Prefer
`let`/`let!` over instance variables in `before`, and keep the values a test depends on visible in
the example. `--order random` should be on; a suite that only passes in declaration order has
inter-test dependencies.

**Doubles.** `instance_double` and `class_double` (verifying doubles) over bare `double`, so the
double rejects methods the real class does not have. `verify_partial_doubles = true`.

**Minitest.** `test/` directory, files ending `_test.rb`, methods prefixed `test_`, or the spec DSL.
Same rules apply.

## Sources

- Jest configuration defaults — https://jestjs.io/docs/configuration
- Vitest mocking guide — https://vitest.dev/guide/mocking
- Node.js `node:test` — https://nodejs.org/api/test.html
- Mock Service Worker philosophy — https://mswjs.io/docs/philosophy
- Testing Library guiding principles — https://testing-library.com/docs/guiding-principles
- pytest good practices — https://docs.pytest.org/en/stable/explanation/goodpractices.html
- pytest parametrize — https://docs.pytest.org/en/stable/how-to/parametrize.html
- JUnit 5 user guide — https://docs.junit.org/current/user-guide/
- Maven Surefire inclusions — https://maven.apache.org/surefire/maven-surefire-plugin/examples/inclusion-exclusion.html
- Go `testing` package — https://pkg.go.dev/testing
- Go table-driven tests — https://go.dev/wiki/TableDrivenTests
- Microsoft Learn, *Best practices for writing unit tests* — https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices
- RSpec documentation — https://rspec.info/documentation/
