---
description: MUST invoke when writing, updating, or fixing end-to-end or browser tests — Playwright, Cypress, Selenium, WebDriver, or device automation that drives the assembled application as a user. Also use when an E2E suite is slow, flaky, or failing, or when someone proposes covering a change with a UI test.
---

# E2E Test Manager

## Overview

Authors and maintains tests that drive the assembled system the way a user does. This level buys
fidelity — proof that the pieces are wired together and the critical journeys work — at the highest
cost per test in runtime, flakiness, and diagnosis. The first job of this skill is to keep the level
small; the second is to make the tests that belong here deterministic.

## Is This the Right Skill?

| The behavior needs | Skill |
|--------------------|-------|
| A user driving the assembled system through its real interface | this one |
| A real DB, HTTP server, queue, or filesystem, but no user | `necturalabs:integration-test-manager` |
| Only our code, one process, no I/O | `necturalabs:unit-test-manager` |
| More than one of the above, or a suite-wide audit | `necturalabs:test-manager` |

<HARD-GATE>
**Before writing an E2E test, prove it cannot be a lower-level test.** Google's published ratio is
roughly 70% unit, 20% integration, 10% end-to-end. An E2E test that fails does not say what broke —
the defect could be anywhere in the system — and its cost is paid on every CI run forever.

Add one only for a journey that is critical to the business AND crosses boundaries no lower level
can observe. Validation rules, calculations, error mapping, and conditional rendering are all
cheaper and sharper one or two levels down.
</HARD-GATE>

## House Rules

<HARD-GATE>
1. **Test our code, never a library or framework.** Assume third-party code works. If a test would
   fail when a dependency changes its output while our code is unchanged, it is testing the
   dependency — a component library's markup and a chart library's SVG included. Wrap the dependency
   and test our wrapper's behavior instead.
2. **Never assert on human-readable copy.** Marketing sentences, labels, error prose, formatted
   dates, currency strings, and whole rendered or serialized documents change for non-behavioral
   reasons. Assert roles, ids and `data-*` attributes, element counts, status codes, error codes and
   types, and state. When the copy genuinely IS the requirement — a legal disclaimer, a regulated
   notice, a wire-protocol constant — assert the identifier the application renders it from (the
   message key, id, or code), never a duplicated literal sentence.
3. **Every new test must be observed failing** for the reason it claims before it counts as passing.
4. **Never weaken a test to get green.** Not by relaxing an assertion, widening a tolerance,
   marking `skip`/`only`/`xfail`, raising a retry count to hide a race, wrapping a step in a
   conditional, or deleting it. A failing test means the code is wrong (fix the code) or the
   requirement changed (see the upsert matrix below).
5. **Never encode a known bug as expected behavior.** If writing a test reveals a defect, fix the
   defect. A green test that pins a bug in place is worse than no test.
6. **You ran it, you own it.** A test that failed, flaked, or was skipped in a run you performed is
   yours to deal with. The only question is whether you fix it or report it — never whether to
   mention it. Fix it in the current work when it sits in what you changed; fix it in its own commit
   when it is small and self-contained, which a flaky or skipped test almost always is. Report it,
   with file:line and how big the fix looks, when fixing would swamp the intended change, when the
   problem spans the whole suite, or when the failure exposes a bug in untested or legacy code whose
   current behavior may be load-bearing — there, establish coverage before changing what you cannot
   verify. "Different module", "predates my change", "unrelated to this task"
   and "out of scope" are never reasons to stay silent, and rarely reasons not to fix. Dismissing it
   requires establishing it is not a defect, and citing the evidence for that.
7. **Test our application, never a third party.** Do not navigate to sites you do not control, and
   do not drive an external identity provider's UI. Mock the external service or use a controlled
   test tenant. Their cookie banner is not your test's problem, but it will be your failure.
</HARD-GATE>

## Workflow

1. **Discover the setup** — the runner and its config, base URL, how the app under test is started,
   how authentication is obtained, where fixtures and page objects live, and the command that runs
   one spec.
2. **Justify the level.** Write the journey as a sentence. If any step's risk is coverable lower
   down, cover it there instead and keep this test to the wiring.
3. **Decide add / update / leave** using the upsert matrix below. A UI restructure that preserves
   behavior should not change a test that was written against roles and ids; if it does, the test
   was written against the DOM.
4. **Set up state through the API, not the UI.** Log in programmatically, seed data
   programmatically, and start the test at the screen the journey begins on.
5. **Write the test** with auto-waiting assertions and no fixed delays. See
   `references/e2e-test-rules.md`.
6. **Observe it fail.** Break the behavior it covers and confirm the failure names the right step.
7. **Run it repeatedly** — at least five consecutive passes, and in the CI configuration if it
   differs. A single green run says nothing at this level.
8. **Triage anything else the run surfaced** under House Rule 6, classifying each defect
   against `../test-manager/references/test-taxonomy.md` — flaky, skipped, assertion-free,
   unfailable, tautological, copy-asserting, library-testing, change-detector, duplicated,
   obsolete, mislabeled, excessive setup.

### When dispatched by `necturalabs:test-manager`

- Run only your level's command, never the full suite.
- Do not edit shared fixtures, factories, auth setup files, or any helper outside your assigned
  paths — another specialist may be editing it right now. Report the change you need instead.
- Do not run the code review. Report back; the orchestrator runs it once over everything.

## The Upsert Decision

Google's rule: strive for unchanging tests. After a test is written, it should not need to change as
the system is refactored, extended, or fixed.

| Change | Existing tests | New tests |
|--------|----------------|-----------|
| **Pure refactoring** | unchanged. If they break, either the refactoring changed behavior or the tests were written against implementation details — fix that cause, not the assertion. | none |
| **New feature** | unchanged | add, covering the new behaviors only |
| **Bug fix** | unchanged | add a regression test, written first and observed failing |
| **Behavior change** | **the only case where editing an existing test is legitimate** | add for genuinely new behavior |

That matrix governs what a test asserts about *product* behavior. Repairing a test that is itself
defective — no assertion, tautological, asserting copy, asserting a generated query, unfailable,
flaky — is a different axis, and is always allowed regardless of what the product did. If the test
is currently failing, establish *why* before repairing it: a defective test can still be failing for
a real product reason, and repairing it green hides that. Confirm the product behavior is correct
first, then repair, then observe the repaired test fail against the broken behavior. Name the
defect from the catalogue (`../test-manager/references/test-taxonomy.md`) before you touch the test.

Deleting a test is legitimate in four cases: the behavior it covers no longer exists, it duplicates
another test at the same level, it is itself defective with no salvageable assertion, or the
behavior is now covered at a cheaper level and that replacement was written and observed failing
first. Say which case applies. "It was failing" and "it was slow" are never reasons to delete a test.

## Quick Reference

Full rules with sources: `references/e2e-test-rules.md`

| Concern | Rule |
|---------|------|
| Selectors | Role and accessible name first; a dedicated `data-testid` when there is no accessible handle. Never CSS class chains, never XPath, never nth-child, never a text sentence. |
| Waiting | Web-first assertions that retry until the condition holds. Never a fixed sleep. Wait on a network alias or a state change, not a duration. |
| Auth | Programmatic login, reused storage state. Never drive the login form in `beforeEach`. |
| Data | The test creates and owns its data, keyed uniquely. Never rely on what a previous test left. |
| Isolation | Fresh browser context per test: no shared cookies, storage, or session. |
| Cleanup | Reset before the test, not after — an aborted run leaves `after` hooks unexecuted. |
| Assertions per test | Batch them. A journey test asserts at each meaningful checkpoint; splitting into one-assertion tests multiplies setup cost with no benefit. |
| Third parties | Mocked or stubbed at the network layer. |
| Debugging | Traces and videos on failure, from CI. Screenshots alone rarely explain a race. |
| Runtime | Shard in CI and push coverage down the pyramid. If the suite cannot finish in the time the team will actually wait, move journeys to cheaper levels — deletion only under the four cases above, and never because a test is slow. |

## Rationalizations — All Rejected

| Excuse | Reality |
|--------|---------|
| "An E2E test is quicker to write than restructuring for a unit test" | You pay the write cost once and the run cost forever, with worse diagnosis. |
| "It's flaky, so I'll add a retry" | Retries hide races. Find the condition the test should wait on. |
| "A short sleep is fine here" | It is the number one cause of E2E flake and it will be copied into every new test. |
| "Checking the headline text proves the page rendered" | Assert the URL, the landmark role, or a `data-testid`. Copy changes without defects. |
| "Logging in through the UI is more realistic" | Cover login once, in its own test. Everywhere else it is slow, flaky setup. |
| "The staging data already has a suitable user" | Then the test breaks when someone else edits that user. Create your own. |
| "Cleaning up in afterEach keeps it tidy" | An aborted run skips it. Reset at the start. |
| "This test only fails in CI" | That is a real difference in timing or environment, and it is a defect in the test. |
| "One assertion per test is best practice" | That is a unit-test rule. At this level it multiplies the most expensive part. |

## Red Flags — Stop

- `waitForTimeout`, `cy.wait(3000)`, `Thread.sleep`, or any bare duration
- A selector containing a CSS class chain, `nth-child`, XPath, or a full sentence
- A `beforeEach` that logs in through the form
- A test that depends on another test having run first
- A retry count raised to make CI pass
- Conditional branching around a step that "sometimes" appears
- A new E2E test covering logic that a unit test could pin down

## When Done

Report the journey covered and why it needs this level, what you added, updated, and deleted with
reasons, the failing observation for each new test, the exact command and its output, the number of
consecutive clean runs, and every defect triaged.

If you are running as a subagent dispatched by `necturalabs:test-manager`, stop here and report
back — it runs the full suite and the review once, over everything. Otherwise, including when
test-manager invoked this skill inline in your own context, run the full suite yourself and then
`necturalabs:iterative-code-review` over the changes — preceded by
`necturalabs:iterative-security-audit` when the changes fall in that skill's trigger list (see its
description; it is broader than auth and crypto), since it chains into the review. That run satisfies the orchestrator's completion
gate rather than adding a second one. If the review returns test findings, fix them here
under these rules rather than re-entering a test skill, so the review runs once per invocation
chain.
