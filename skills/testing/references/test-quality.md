# Test Quality

Applies at every level. Level-specific detail lives in `unit.md`, `integration.md`, and `e2e.md`.

## Contents

- [Behavior versus implementation](#behavior-versus-implementation)
- [Classifying a test by what it does](#classifying-a-test-by-what-it-does)
- [Structure and naming](#structure-and-naming)
- [Assertion discipline](#assertion-discipline)
- [Test doubles](#test-doubles)
- [Determinism](#determinism)
- [Diagnosing a flake](#diagnosing-a-flake)
- [Triage catalogue](#triage-catalogue)
- [Coverage and mutation testing](#coverage-and-mutation-testing)
- [Sources](#sources)

## Behavior versus implementation

A behavior is a guarantee the system makes about how it responds to inputs in a given state. Test
through the public surface — the one other code or users actually call — not through a private
method reached by reflection or an escape hatch. When a private method feels like it needs its own
test, that's usually a sign it should be extracted into something with its own public surface.

Don't test the trivial: getters, plain data holders, generated code, constructors with no logic.
Spend the coverage on branches, calculations, validation, error handling, and state transitions —
weighted by risk, so money, auth, and permissions get the most exhaustive treatment.

A test that would fail if a dependency changed its output while your own code stayed the same is
testing the dependency, not your code. Assume third-party code works; wrap it and test the wrapper's
decisions — which inputs it forwards, which defaults it applies, how it translates errors.

## Classifying a test by what it does

Directory names and file suffixes lie. Classify by what actually runs:

| Observation | Actual level |
|---|---|
| Every collaborator is a double; no socket, no file, no container | Unit — regardless of the folder |
| Starts a container, hits a real DB or HTTP server, or writes real files | Integration |
| Drives a browser, a device, or the deployed binary through its real entry point | E2E |
| Mocks the HTTP client and asserts the request that was sent | Usually a change-detector test of the client wrapper, not real integration coverage |
| Boots the whole application to exercise one pure function | Mislabeled — a unit test paying integration costs |

A mislabeled test is a real finding, not a nitpick: it distorts the level ratio, runs at the wrong
point in CI, and hides its true cost.

## Structure and naming

Arrange–Act–Assert (equivalently Given–When–Then): three visually separated phases, exactly one act.
Multiple acts in one test hide which one broke, and assertions after the first failure never run.

Name the behavior, not the method — `calculateTotal_emptyCart_returnsZero`,
`should_reject_withdrawal_when_balance_is_empty`, or a descriptive sentence are all fine; consistency
within a project matters more than the exact convention. Never `test1` or the bare method name — the
name is what a reader sees in a failure report before opening the file. If the name needs "and," it's
two tests.

No logic in tests: no loops, conditionals, arithmetic, or string-building to *compute* an expected
value — use literal expected values and the framework's parameterized/table support instead of a
loop. This doesn't ban parsing the *actual* output to assert on its fields; when the result is
markup, a document, or a serialized payload, parse it and assert on structure rather than compare the
whole rendered string. Never compute the expected value using the code under test's own logic or
helpers — that makes the assertion true by construction and the test unable to fail for the reason
that matters.

Prefer duplication that keeps a test self-evident (DAMP) over indirection that saves a few lines
(DRY) — a value the test depends on belongs in the test body even at the cost of repeating it across
tests; push only genuinely irrelevant boilerplate into shared setup.

## Assertion discipline

Assert the properties the behavior actually guarantees, not the whole object graph or a golden file
— a wide assertion fails on unrelated changes and buries the real difference in noise. Use the
assertion form that names the subject (`assertThat(...)`) over a bare boolean, so a failure message
says what was expected rather than just that something was false.

Prefer state assertions — the result, or the resulting state — over interaction assertions. Verify
that a call happened only when the call itself *is* the observable behavior (an email sent, a record
written, a payment charged) or when frequency is the point (a cache that must not re-query).
Interaction assertions elsewhere couple the test to *how* the result was reached rather than *what*
it is, and break on refactors that change nothing observable.

## Test doubles

Preference order, strongest first:

1. **The real implementation**, when it's fast, deterministic, and has simple dependencies. More
   confidence than any double.
2. **A fake** — a working in-memory implementation of the same contract. Worth building once several
   tests need it; a low-fidelity fake is worse than none, so a fake needs its own tests against the
   contract it claims to satisfy.
3. **A stub** — hardcoded returns used only to steer the system into the state a test needs. Every
   stubbed call should trace to a specific assertion in that test.
4. **Interaction assertions** — last resort, for the reasons above.

Don't mock what you don't own: wrap a third-party API in an adapter you control, then double the
adapter. Mocking a library's surface directly couples the suite to a shape you can't change and can't
verify. When mock setup outweighs the arrange-and-assert, the production code needs a seam, not the
test more mocks — two or three doubles per test is a practical ceiling. A direct call to the system
clock, a random source, an environment variable, or a global singleton needs an injected seam before
it can be tested from outside; that's a production-code change, and the right one.

## Determinism

- Wrap the clock; inject it and freeze it in tests. Never assert against "now."
- Inject or seed randomness and id generation.
- Never sleep for asynchronous work — poll the condition, subscribe to the event, or use the
  runner's fake-timer support. A fixed sleep racing a variable delay is the most common single cause
  of flake at every level above unit.
- No shared mutable state and no ordering dependency between tests. Reset doubles between tests
  explicitly where the runner doesn't do it by default.

## Diagnosing a flake

Treat a flaky test as strictly worse than one that fails consistently — it trains everyone to
re-run red builds instead of trusting them. Diagnose before touching anything:

1. Re-run enough times to measure a real rate, not a guess — more runs when the rate looks low.
2. Look first for a sleep racing a variable delay, shared state between tests, ordering dependence
   (run the level with randomized order and see if results change), or a resource that leaks across
   runs.
3. Root-cause it: replace the sleep with a poll or subscription, isolate the shared state, shrink
   scope, or wrap the ambient dependency causing the variance.
4. Never fix a flake by adding a retry, raising a timeout until it stops reproducing, or marking it
   skipped with no plan to return — that's quarantine, and quarantine with no exit date is deletion
   with extra steps.

## Triage catalogue

Every entry here is a defect worth fixing in the current work, or in its own small commit — never a
reason to look away.

| Defect | How to spot it | Fix |
|---|---|---|
| Flaky | Same code, different results across runs | Root-cause per the diagnosis steps above; never retry-until-green |
| Skipped / quarantined | `skip`, `xfail`, `only`, commented out, `.disabled` | Fix and re-enable, or delete under a legitimate deletion case |
| Assertion-free | Calls code, asserts nothing (or only that it didn't throw) | Add the assertion the name promises, or delete it |
| Unfailable | Passes identically against broken and fixed code | Re-derive what it was meant to pin down |
| Tautological | Expected value computed with the production code's own logic | Replace with a literal expected value |
| Copy-asserting | Asserts a rendered sentence, label, or whole document | Assert roles, ids, counts, codes, state instead |
| Library-testing | Would fail if a dependency's output changed with our code unchanged | Move the assertion onto the wrapper's behavior |
| Change-detector | Asserts generated query text, exact call arguments, or call sequence | Assert the returned data or resulting state instead |
| Duplicated | Two tests pin the same behavior at the same level | Keep the clearer one |
| Obsolete | Pins behavior the product no longer has | Delete it |
| Mislabeled | Runtime behavior doesn't match the level it's filed under | Move it to the right suite and command |
| Excessive setup | Setup dwarfs the assertion | Push construction into named builders with sensible defaults |

## Coverage and mutation testing

Coverage measures which lines ran, not whether anything was checked — a suite of assertion-free tests
reaches high coverage and catches nothing. Treat a coverage drop as a prompt to look, not a target to
chase for its own sake; roughly 60% is a reasonable floor, 75% solid, 90% excellent, with no top-down
mandate that ignores risk. Mutation testing — inject a small change into the production code and see
if the suite catches it — is the stronger signal; the same idea done by hand (break the line the test
claims to cover, watch it fail, restore it) is how a single new test earns its keep.

## Sources

- *Software Engineering at Google*, ch. 11–14 — https://abseil.io/resources/swe-book/html/ch11.html
- Google Testing Blog, *Just Say No to More End-to-End Tests* — https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html
- Google Testing Blog, *Change-Detector Tests Considered Harmful* — https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html
- Google Testing Blog, *Flaky Tests at Google and How We Mitigate Them* — https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html
- Google Testing Blog, *Code Coverage Best Practices* — https://testing.googleblog.com/2020/08/code-coverage-best-practices.html
- Martin Fowler, *UnitTest*, *TestPyramid*, *Eradicating Non-Determinism in Tests* — https://martinfowler.com/bliki/UnitTest.html
- Kent Beck, *Test Desiderata* — https://testdesiderata.com/
- Vladimir Khorikov, *Unit Testing Principles, Practices, and Patterns*, ch. 4
- Stryker Mutator, mutation testing — https://stryker-mutator.io/docs/
