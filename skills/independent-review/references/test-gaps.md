# Test gaps

The reviewer's view of the change's tests: whether the coverage is adequate, honest, and
able to fail. This is not how to write a test — when a test has to be written, repaired or
removed, that work goes through the repository's testing skill. Here the question is only
whether what the diff ships is enough, and whether it proves what it claims.

A test suite that cannot fail is worse than none, because it reports safety that is not
there. Most of the checks below are aimed at exactly that.

## 1. Is the changed behavior covered?

| The diff | Expectation |
|---|---|
| Changes behavior a caller can observe | Automated coverage for the new behavior, or a stated reason it is impractical plus the verification actually used |
| Fixes a bug | A regression test that was written **first** and seen failing against the unfixed code |
| Adds a branch, a boundary or an error path | The branch, both sides of the boundary, and the error path are each reached by an assertion |
| Changes a contract, schema or wire format | A test pinning the new shape, and one showing the compatibility path still holds |
| Only moves or renames code | No new test is owed; the existing ones must still cover it |
| Adds a trivial accessor, a data holder, generated code or a constructor with no logic | No test is owed. Demanding one is a finding against the review, not the change |

A change that adds no coverage is not automatically a finding. A change that adds no
coverage **and** alters behavior a caller can observe is one, at HIGH.

## 2. Is it at the right level?

Coverage belongs as low in the pyramid as it can honestly sit.

- **Unit** by default: the behavior is ours and the collaborators are cheap and
  deterministic.
- **Integration** only where a real collaborator — database, HTTP boundary, queue,
  filesystem — *is* the behavior under test. A mocked database in an integration test is
  a unit test wearing a costume.
- **End to end** only for a critical journey nothing lower can observe.

Flag a test pushed up the pyramid for no reason: it is slower, flakier, and it fails for
more reasons than the one it claims. Flag the inverse too — a mocked-out unit test
asserting an integration behavior proves only that the mock was configured.

Do not flag a missing test at a higher level for behavior already covered below it.

## 3. Can it fail?

**Every new test must have been observed failing for the behavior it asserts** — failing for
*that* reason, not on a compile error, a setup error or an unrelated failure. For a bug fix that
is the red run before the fix. For anything else any credible demonstration counts: running it
before the implementation exists, or temporarily breaking the behavior it asserts. Do not require
a particular ritual, and do not require a scripted mutate-and-restore pass on every ordinary test;
require only that the author can say how they saw it fail. A new test nobody can account for that
way is a HIGH finding, whatever its coverage number.

Shapes that pass regardless of correctness:

| Shape | Tell |
|---|---|
| Tautological | The expected value is computed by the code under test, or by a copy of its logic |
| The liar | Nothing it asserts can be false — an assertion on a value the test itself just set, with no call between |
| Line hitter | The code runs, nothing is asserted about the result |
| Assertion roulette | Many assertions, no way to tell which failed or why |
| Fragile | Breaks on a refactor that changes no behavior, because it asserts internals |
| The inspector | Reaches private state by reflection or by a back door added for the test |
| Free ride | New behavior asserted by adding a line to an existing test rather than by a new one |

## 4. Does it test our code?

Test our behavior, and our integration assumptions about a dependency where the risk
warrants it. Do not test a library or framework's own internals — those tests fail on
upgrades and prove nothing about this codebase.

Mocks are a design signal. In a unit test, use the cheapest double that keeps the test
honest; at integration level prefer the real collaborator. More mock setup than assertion
means the production code needs a seam — report the seam, not the mock count. Wrap an
external API when the wrapper is a useful application boundary, never solely to make a
test possible.

## 5. Is it honest under change?

A green run obtained by weakening a test is a defect that hides a defect. Flag any of
these in the diff unless the author names which legitimate case applies:

- An assertion relaxed, a tolerance widened, an exact value replaced by a looser matcher.
- A skip, exclusive-run or expected-failure marker added.
- A retry, a longer timeout or a sleep introduced around a failure — that is a race being
  papered over, and the race is the finding.
- A test deleted.

Deletion is legitimate in four cases only, and the diff must say which: the behavior no
longer exists; the test duplicates another at the same level; the test was itself
defective with nothing salvageable; or the behavior is now covered more cheaply by a
replacement that was written and seen failing first.

An existing test is legitimately edited when the intended contract changed, when the diff
extends the same structure — a case table, a fixture, a helper — or when the test itself
was defective. Never to make an incorrect implementation pass. A product bug gets a new
regression test; editing an existing test to accommodate a fix destroys the evidence that
the fix was needed.

**Never encode a known bug as expected behavior.** A passing test asserting the buggy
output pins the bug in place and guards it against repair. CRITICAL, always.

## 6. Is it deterministic?

| Check | Severity |
|---|---|
| The clock, randomness or id generation is real rather than injected | HIGH |
| An arbitrary sleep stands in for an explicit signal, a fake timer or a bounded wait on a condition | HIGH |
| Shared mutable state between tests, or a dependence on execution order | HIGH |
| State established by a previous test rather than by this one's setup | HIGH |
| A resource — file, socket, container, transaction — not released in teardown | MEDIUM |
| An external file or fixture the test depends on but does not make visible | MEDIUM |

Teardown releases; it never sets up the next test.

## 7. Do the assertions assert the right thing?

- **Results and state**, not calls. Assert interactions, exact arguments, generated
  queries or serialized output only where that output *is* the contract — an adapter, a
  protocol, a wire format.
- **Never assert on presentation copy** unless the wording itself is the requirement:
  legal text, command-line output, protocol error strings, an acceptance criterion.
  Otherwise assert ids, roles, structural attributes, counts, codes, types and state.
  Where a specific string genuinely is the requirement, assert the identifier it is
  rendered from — the key, id or code — never a duplicated sentence.
- **No logic in tests.** Literal expected values, parameterized cases instead of loops,
  no conditionals, no string assembly. A loop in a test is a bug waiting in the test.
- **One behavior per test, one act.** A name containing "and" is the tell.
- Duplication in tests is acceptable where it makes them self-evidently correct. Do not
  file a finding for a test that repeats a literal rather than reaching for a helper.

## 8. What the reviewer requires as evidence

- The command that was run and what it printed. "Tests pass" without output is not a
  verification, and a review that accepts it has verified nothing.
- Which tests are new, and how each was seen to fail.
- What was **not** run — a suite that is CI-only, a platform not available locally — said
  plainly rather than left implied.

## Not a finding

- A coverage percentage. Coverage is a diagnostic, never a target, and high coverage with
  weak assertions is the line-hitter shape above.
- A missing test for trivial or generated code.
- A naming scheme that differs from a favorite convention while still stating what is
  tested, under what conditions, and what is expected.
- Duplication between tests that keeps each one readable on its own.
- A pre-existing weak test in a file the diff merely touched — report it once, with
  location and size, and let the change proceed.

## Severity

| Severity | Finding |
|---|---|
| CRITICAL | A test asserts known-buggy behavior as correct · a test was weakened or deleted to turn a real failure green |
| HIGH | Changed observable behavior with no coverage and no stated alternative verification · a bug fixed with no regression test seen red first · a new test never observed failing · a test that cannot fail · non-determinism by construction |
| MEDIUM | Coverage at the wrong level · over-mocking that signals a missing seam · asserting presentation copy · logic inside a test · resources left open |
| LOW | Naming, structure and readability that do not affect what the test proves |
| INFO | A pre-existing weakness in the surrounding suite, raised once |

## Sources

[Google SWE Book, ch. 11–13](https://abseil.io/resources/swe-book) ·
[Fowler, Mocks Aren't Stubs](https://martinfowler.com/articles/mocksArentStubs.html) ·
[Fowler, Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html) ·
[Beck, Test Desiderata](https://kentbeck.github.io/TestDesiderata/) ·
Meszaros, *xUnit Test Patterns* · Khorikov, *Unit Testing Principles, Practices and Patterns*
