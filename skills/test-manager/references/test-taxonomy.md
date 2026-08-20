# Test Taxonomy and Triage

## Contents

- [Deciding the level for new work](#deciding-the-level-for-new-work)
- [Classifying tests that already exist](#classifying-tests-that-already-exist)
- [Test sizes and hermeticity](#test-sizes-and-hermeticity)
- [Triage catalogue — defects in an existing suite](#triage-catalogue--defects-in-an-existing-suite)
- [Portfolio shape](#portfolio-shape)
- [Sources](#sources)

## Deciding the level for new work

Ask what the behavior needs in order to be observed, then pick the cheapest level that can observe
it. Push down the pyramid until the level genuinely cannot see the behavior.

| Question | Answer | Level |
|----------|--------|-------|
| Can the behavior be observed by calling our code in one process with no I/O? | yes | unit |
| Does the behavior only appear when our code talks to a real collaborator (DB, HTTP, queue, filesystem, clock-driven infrastructure)? | yes | integration |
| Does the behavior only appear when a user drives the assembled system end to end? | yes | e2e |

Two rules keep this honest:

- **The wiring itself is a behavior.** "The query returns the right rows" is integration. "The
  totals are computed correctly" is unit, even if the numbers come from a query in production.
- **A journey is not a feature list.** If an E2E test is being written because several units were
  changed, it is a bundle of unit tests wearing a costume. E2E covers the journey, not the parts.

### Solitary vs sociable units

Fowler's distinction, and both are unit tests: a **solitary** test replaces every collaborator with
a test double; a **sociable** test lets the unit call real collaborators that are fast and
deterministic. Google's *Software Engineering at Google* prefers realism — use the real
implementation when it is fast, deterministic, and has simple dependencies. Neither style makes a
test an integration test. What makes it an integration test is a real out-of-process collaborator.

### Narrow vs broad integration

Fowler again: a **narrow** integration test exercises only the part of our code that talks to one
external service, with that service real or contract-verified. A **broad** integration test stands
up several live services at once. Prefer narrow. Broad integration tests carry E2E costs without
E2E coverage, and their failures do not localize.

## Classifying tests that already exist

Directory names lie. Classify by what the test actually does at runtime:

| Observation | Actual level |
|-------------|--------------|
| Every collaborator is a double; no socket, no file, no container | unit — regardless of the folder it sits in |
| Starts a container, hits a real DB or HTTP server, or writes real files | integration |
| Drives a browser, a device, or the deployed binary through its public entry point | e2e |
| Mocks the HTTP client and asserts the request that was sent | unit test *of the client wrapper* — and usually a change-detector; see the triage catalogue |
| Boots the whole application framework to test one pure function | mislabeled — it is a unit test paying integration costs |

A mislabeled test is a real finding: it distorts the ratio, runs in the wrong CI stage, and hides
its true cost. Report it and move it.

## Test sizes and hermeticity

Google classifies by resources rather than by scope:

- **Small** — one process, one thread, no sleeping, no I/O. Fast and deterministic; developers can
  run thousands of them in their normal workflow.
- **Medium** — one machine, multiple processes allowed, localhost networking allowed.
- **Large** — anything beyond one machine.

Two properties trade off against each other for anything larger than a unit test:

- **Hermeticity** — how isolated the system under test is from anything outside it. Higher
  hermeticity means fewer cross-test conflicts and no environment reservations.
- **Fidelity** — how closely the system under test reflects production.

Choose the most hermetic setup that still has the fidelity the behavior needs, and say which you
chose. "Shared staging environment" is the lowest-hermeticity option and the usual root cause of a
suite nobody trusts.

## Triage catalogue — defects in an existing suite

Every entry here is a defect you now own. Fix it in the current work, or in its own commit when it
is small and self-contained — which most of these are. Reporting it with file:line and a size
estimate is the fallback for a fix that would swamp the change or spans the whole suite; it is never
a way to stay silent.

| Defect | How to spot it | Fix |
|--------|----------------|-----|
| **Flaky** | Same code, different results across runs. Establish the rate by re-running. | Root-cause it: unwrap a real clock, poll instead of sleeping, isolate shared state, shrink the scope. Never retry-until-green, never delete. |
| **Skipped / quarantined** | `skip`, `xfail`, `only`, `t.Skip`, commented-out, `.disabled` | Fix and re-enable, or delete under one of the four deletion cases, naming the case. It survives only on an explicit user instruction to keep it. A quarantine with no exit date is deletion with extra steps. |
| **Assertion-free** | Test calls code and asserts nothing, or only that it did not throw | Add the assertion the name promises, or delete the test. |
| **Unfailable** | Passes identically against the broken and fixed code | Re-derive what it was meant to pin down, then observe it fail. |
| **Tautological** | Expected value computed with the production code's own logic or by calling the code under test | Replace with a literal expected value. |
| **Copy-asserting** | Asserts a rendered sentence, label, marketing string, formatted date, or a whole document byte for byte | Assert roles, ids, `data-*` attributes, counts, codes, and state instead. |
| **Library-testing** | Would fail if a dependency changed its output while our code stayed the same | Move the assertion onto our wrapper's behavior, or delete it under case 3 — defective with no salvageable assertion. |
| **Change-detector** | Asserts generated SQL text, exact call arguments, or an internal call sequence rather than the result | Assert the returned data or the resulting state. Interaction assertions only where the interaction *is* the behavior. |
| **Duplicated** | Two tests pin the same behavior at the same level | Keep the clearer one, delete the other. Duplicates at *different* levels are usually fine. |
| **Obsolete** | Pins behavior the product no longer has | Delete it. A test for removed behavior is a change preventer. |
| **Mislabeled** | Level does not match runtime behavior (see above) | Move it to the right suite and command. |
| **Excessive setup** | Setup dwarfs the assertion; readers scroll away to understand the test | Push construction into named builders with defaults; keep the values the test cares about inline. |

Flaky tests deserve their own note: Google treats a consistently failing test as strictly better than
a flaky one, because a flaky test destroys trust in every other result. Fowler's remedies map onto
the causes — isolate tests from each other, never sleep for asynchronous work (poll or subscribe),
wrap the system clock so it can be substituted, replace remote services with doubles, and keep
resource pools small so leaks surface immediately.

## Portfolio shape

- Google's published ratio is roughly **70% unit / 20% integration / 10% end-to-end**; the SWE Book
  frames it as about **80% small tests / 20% larger ones**, classified by resources rather than by
  scope. Treat these as a shape, not a quota.
- **Coverage is a diagnostic, not a goal.** Google's own guidance offers 60% as acceptable, 75% as
  commendable, and 90% as exemplary, while explicitly rejecting top-down mandates and warning that
  high coverage with weak assertions is worthless. Mutation testing — kill rate against injected
  mutants — measures assertion strength in a way line coverage cannot.
- The suite has to finish fast enough that people keep running it. Fowler's benchmark for the
  commit build is ten minutes.

## Sources

- *Software Engineering at Google*, ch. 11 *Testing Overview* (test sizes, the 80/20 mix) — https://abseil.io/resources/swe-book/html/ch11.html
- *Software Engineering at Google*, ch. 12 *Unit Testing* — https://abseil.io/resources/swe-book/html/ch12.html
- *Software Engineering at Google*, ch. 13 *Test Doubles* — https://abseil.io/resources/swe-book/html/ch13.html
- *Software Engineering at Google*, ch. 14 *Larger Testing* — https://abseil.io/resources/swe-book/html/ch14.html
- Google Testing Blog, *Just Say No to More End-to-End Tests* — https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html
- Google Testing Blog, *Change-Detector Tests Considered Harmful* — https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html
- Google Testing Blog, *Code Coverage Best Practices* — https://testing.googleblog.com/2020/08/code-coverage-best-practices.html
- Google Testing Blog, *Flaky Tests at Google and How We Mitigate Them* — https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html
- Martin Fowler, *UnitTest* — https://martinfowler.com/bliki/UnitTest.html
- Martin Fowler, *IntegrationTest* — https://martinfowler.com/bliki/IntegrationTest.html
- Martin Fowler, *Eradicating Non-Determinism in Tests* — https://martinfowler.com/articles/nonDeterminism.html
- Martin Fowler, *TestPyramid* — https://martinfowler.com/bliki/TestPyramid.html
- Martin Fowler, *Continuous Integration* ("Keep the Build Fast") — https://martinfowler.com/articles/continuousIntegration.html
- Stryker Mutator, mutation testing — https://stryker-mutator.io/docs/
