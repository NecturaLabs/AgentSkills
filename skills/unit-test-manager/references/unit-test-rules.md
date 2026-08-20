# Unit Test Authoring Rules

Review criteria for tests already written live in
`../../iterative-code-review/references/testing-rules.md`. This file is the authoring procedure:
what to write, what to leave out, and how to structure it. Tests produced here must also clear the
review checklist.

## Contents

- [What to test, and what not to](#what-to-test-and-what-not-to)
- [Structure and naming](#structure-and-naming)
- [Complete and concise](#complete-and-concise)
- [Assertions](#assertions)
- [Test doubles](#test-doubles)
- [Determinism](#determinism)
- [Parameterized and property-based tests](#parameterized-and-property-based-tests)
- [Judging a test you just wrote](#judging-a-test-you-just-wrote)
- [Coverage and mutation testing](#coverage-and-mutation-testing)
- [Sources](#sources)

## What to test, and what not to

**Test behaviors, not methods.** A behavior is any guarantee the system makes about how it responds
to a series of inputs while in a particular state. One method often carries several behaviors and
several edge cases; write one test per behavior. If a test name contains "and", it is two tests.

**Test through the public API.** Invoke the system the way its callers do. "Public" means the
surface exposed to other teams or modules, not whatever a language keyword marks public. When a
private method feels like it needs its own test, that is a signal to extract it into a unit with its
own public surface — not a reason to reach through the boundary with reflection or an escape hatch.

**Do not test the trivial.** Skip getters and setters, plain data holders, generated code, and
constructors with no logic. Test branches, calculations, validation rules, error handling, and state
transitions.

**Do not test libraries or frameworks.** Assume they work. The test for code that wraps
`Intl.DateTimeFormat`, an ORM, an HTTP client, or a crypto primitive covers *our* decisions — which
inputs we forward, which defaults we apply, how we translate errors — not the dependency's output
format. A test whose expected value was copied from the dependency's current output fails on the
next dependency upgrade while our code is still correct.

**Do not assert on human-readable copy.** Rendered sentences, labels, error prose, formatted dates,
currency strings, and whole serialized documents change for reasons that are not defects. Assert
roles, ids, `data-*` attributes, counts, status codes, error types and codes, and state. When a
specific string genuinely is the requirement — a legal disclaimer, a wire-protocol constant — assert
its identifier or key, and keep the text itself in one place that is not a test.

**Test at the level the risk deserves.** Money, auth, and permissions earn exhaustive behavioral
coverage. Plumbing and configuration are covered by the tests that use them, or not at all.

## Structure and naming

**Arrange–Act–Assert**, equivalently Given–When–Then, and the same three phases that form the core
of Meszaros's four-phase test (setup, exercise, verify, teardown). Three visually separated
sections, exactly one act. Multiple acts in one test mean you cannot tell which one broke,
and assertions after the first failure never run.

**Name the behavior, not the method.** All three of these are fine, and consistency inside a project
matters more than the choice:

```
Unit_Scenario_ExpectedBehavior      calculateTotal_emptyCart_returnsZero
should_ExpectedBehavior_when_Cond   should_reject_withdrawal_when_balance_is_empty
descriptive sentence                "rejects a withdrawal when the balance is empty"
```

Never `test1`, `testStuff`, or the bare method name. The name is what a reader sees in a failure
report; it should say what broke without opening the file.

**No logic in tests.** No loops, conditionals, arithmetic, or string building to produce an
*expected* value. Logic in a test means the test itself needs a test, and a bug there is invisible.
Use literal expected values, and use the framework's parameterized support instead of looping.

The ban covers computing what the answer should be — it does not cover reading what the code
actually produced. When the result is markup, a document, or a serialized payload, parse it and
assert on the fields under test. Use a real parser where one is available; where none is, extract
the fields in one small named helper shared by the tests. That is the correct alternative to
asserting the whole rendered string, and the helper must only extract — never compute an expectation.

**Never compute the expected value with the production code's logic.** Calling the code under test,
reusing its helper, or duplicating its formula makes the assertion true by construction. Such a test
passes on broken code.

## Complete and concise

A test is **complete** when its body contains everything a reader needs to understand how it reaches
its result, and **concise** when it contains nothing else.

**DAMP over DRY** — Descriptive And Meaningful Phrases. Duplication is acceptable in tests when it
makes them self-evidently correct. Tests do not get the maintainability payoff that DRY buys in
production code, and they pay a much higher clarity cost for indirection.

**Keep cause and effect adjacent.** Ben Yu's rule: relevant, in; irrelevant, out. Values the test
depends on belong in the test body even at the cost of repetition. Only genuinely irrelevant
boilerplate belongs in shared setup.

**Shared setup, done right.** Use setup hooks to construct the object under test and its
collaborators in a default state. Do not let a test depend on a specific value that lives in a setup
method — override it explicitly in the test body. Prefer helper methods and builders with sensible
defaults, where each test names only the fields it cares about.

**Helpers assert one conceptual fact.** A general-purpose `validateEverything(result)` called by
every test produces failures nobody can localize. Test infrastructure shared across suites is
production code for the test suite and needs its own tests.

## Assertions

**Prefer narrow assertions.** Assert the properties the behavior guarantees. Comparing an entire
object graph, a full serialized payload, or a golden file makes every unrelated field a trigger for
failure and buries the one difference that matters in a wall of diff.

**Make failures self-explaining.** Use the assertion form that receives the subject — `assertThat`
and its equivalents — over a bare boolean. "expected to contain <orange>" localizes the bug;
"expected <true> but was <false>" does not.

**One conceptual behavior per test**, which usually means a small cluster of assertions about one
outcome rather than a single assertion or a dozen unrelated ones.

## Test doubles

Preference order, strongest first:

1. **The real implementation** — when it is fast, deterministic, and has simple dependencies. Prefer
   realism over isolation: a test that runs the real collaborator gives more confidence than one
   that assumes a double behaves like it.
2. **A fake** — a working, in-memory implementation that honors the same contract. Worth building
   when many tests need it. A fake with poor fidelity is worse than no fake, so a fake needs its own
   tests against the contract it claims to satisfy.
3. **A stub** — hardcoded return values, used only to steer the system into the state a test needs.
   Each stubbed call should have a direct relationship with an assertion in that test. Stubbing
   leaks implementation details into the test and cannot verify the stubbed behavior is realistic.
4. **Interaction assertions** — verifying that a call happened. Last resort, because they assert
   *how* the result was reached rather than *what* it is. Legitimate when the interaction is the
   observable behavior (an email sent, a record written, a payment charged) or when call frequency
   is the point (a cache that must not re-query). Avoid over-specifying arguments and call counts.

**Don't mock what you don't own.** Wrap third-party APIs in an adapter you control, then use the
adapter's fake or stub. Mocking a library's surface directly couples the suite to a shape you cannot
change and cannot verify.

**Don't over-mock.** When mock setup outweighs the arrange and assert, the production code needs a
seam, not the test more mocks. Two or three doubles per test is a practical ceiling.

**Static and ambient dependencies need seams.** A direct call to the system clock, a random source,
an environment variable, or a global singleton makes the behavior untestable from the outside.
Inject an interface and substitute it. This is a production-code change, and it is the right one.

## Determinism

- **Wrap the clock.** Inject it, freeze it in tests. Never assert against "now".
- **Inject randomness and id generation.** Seed them or replace them.
- **Never sleep for asynchronous work.** Poll for the condition, subscribe to the event, or use the
  runner's fake timers. A fixed sleep racing a variable delay is the single most common flake.
- **No shared mutable state and no ordering dependencies.** Each test builds its own starting
  conditions; cleanup that only happens on success is not cleanup.
- **Reset doubles between tests.** Most runners leave mock state in place unless configured
  otherwise — set the restore option or restore explicitly.

## Parameterized and property-based tests

Parameterized tests replace loops: one test body, a table of cases, one reported result per case
with a name that identifies the case. Every major framework has this — use it rather than iterating
inside a test.

Property-based testing (Hypothesis, fast-check, QuickCheck descendants) generates inputs and shrinks
failures to a minimal counterexample. It complements example-based tests rather than replacing them:
examples pin the behaviors you decided on, properties hunt the edges you did not think of. Good
candidates are round-trips (encode/decode), invariants (result always within bounds), and
equivalence with a simpler reference implementation.

## Judging a test you just wrote

Khorikov's four pillars — a test trades between them, and a test scoring zero on any is not worth
keeping:

- **Protection against regressions** — would it catch a real defect in this code?
- **Resistance to refactoring** — would it stay green through an internal rewrite that preserves
  behavior? Tests coupled to structure produce false alarms that train everyone to ignore failures.
- **Fast feedback** — milliseconds, so it gets run.
- **Maintainability** — can a reader tell what broke without leaving the test body?

Kent Beck's test desiderata is the longer form of the same idea: isolated, composable,
deterministic, fast, writable, readable, behavioral, structure-insensitive, automated, specific,
predictive, inspiring. No property should be given up without getting a more valuable one back.

## Coverage and mutation testing

Coverage measures which lines ran, not whether anything was checked. A suite of assertion-free tests
reaches high coverage and catches nothing. Google's published guidance offers 60% as acceptable, 75%
as commendable, and 90% as exemplary, while rejecting top-down mandates — teams pick the number that
fits the risk. Treat a coverage drop as a prompt to look, never as a target to satisfy.

Mutation testing is the stronger signal: inject small changes into the production code and count how
many the suite kills. A surviving mutant is a behavior nothing asserts on, regardless of coverage.
The same technique done by hand — break the line, watch the test fail, restore it — is how a single
new test earns its keep.

## Sources

- *Software Engineering at Google*, ch. 12 *Unit Testing* — https://abseil.io/resources/swe-book/html/ch12.html
- *Software Engineering at Google*, ch. 13 *Test Doubles* — https://abseil.io/resources/swe-book/html/ch13.html
- Google Testing Blog, *Test Behaviors, Not Methods* — https://testing.googleblog.com/2014/04/testing-on-toilet-test-behaviors-not.html
- Google Testing Blog, *Test Behavior, Not Implementation* — https://testing.googleblog.com/2013/08/testing-on-toilet-test-behavior-not.html
- Google Testing Blog, *Change-Detector Tests Considered Harmful* — https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html
- Google Testing Blog, *Don't Put Logic in Tests* — https://testing.googleblog.com/2014/07/testing-on-toilet-dont-put-logic-in.html
- Google Testing Blog, *Tests Too DRY? Make Them DAMP!* — https://testing.googleblog.com/2019/12/testing-on-toilet-tests-too-dry-make.html
- Google Testing Blog, *Keep Cause and Effect Clear* — https://testing.googleblog.com/2017/01/testing-on-toilet-keep-cause-and-effect.html
- Google Testing Blog, *Prefer Narrow Assertions in Unit Tests* — https://testing.googleblog.com/2024/04/prefer-narrow-assertions-in-unit-tests.html
- Google Testing Blog, *Code Coverage Best Practices* — https://testing.googleblog.com/2020/08/code-coverage-best-practices.html
- Martin Fowler, *UnitTest* — https://martinfowler.com/bliki/UnitTest.html
- Martin Fowler, *Mocks Aren't Stubs* — https://martinfowler.com/articles/mocksArentStubs.html
- Martin Fowler, *GivenWhenThen* — https://martinfowler.com/bliki/GivenWhenThen.html
- Martin Fowler, *TestDrivenDevelopment* — https://martinfowler.com/bliki/TestDrivenDevelopment.html
- Martin Fowler, *Eradicating Non-Determinism in Tests* — https://martinfowler.com/articles/nonDeterminism.html
- Microsoft Learn, *Best practices for writing unit tests* — https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices
- Kent Beck, *Test Desiderata* — https://testdesiderata.com/
- Vladimir Khorikov, *Unit Testing Principles, Practices, and Patterns*, ch. 4 — https://www.manning.com/books/unit-testing
- Gerard Meszaros, *xUnit Test Patterns: Refactoring Test Code* (Addison-Wesley, 2007); companion site at http://xunitpatterns.com/ (HTTP only — the host refuses HTTPS)
- Hypothesis, property-based testing — https://hypothesis.readthedocs.io/
- Stryker Mutator, mutation testing — https://stryker-mutator.io/docs/
