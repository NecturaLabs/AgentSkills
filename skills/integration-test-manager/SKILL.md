---
description: MUST invoke when writing, updating, or fixing tests that cross a process boundary — repositories and queries against a real database, HTTP clients and API handlers, message queues, caches, filesystem access, or a service talking to another service. Also use when a test needs Testcontainers, a test database, a stubbed HTTP server, or contract verification.
---

# Integration Test Manager

## Overview

Authors and maintains tests that exercise our code against a real collaborator across a process
boundary. The value of this level is fidelity — proving that the query, the serialization, the
migration, the transaction, and the protocol actually work. Every shortcut that trades away that
fidelity turns an integration test into a slow unit test with worse failure messages.

## Is This the Right Skill?

| The behavior needs | Skill |
|--------------------|-------|
| A real DB, HTTP server, queue, cache, or filesystem | this one |
| Only our code, one process, no I/O | `necturalabs:unit-test-manager` |
| A user driving the assembled system | `necturalabs:e2e-test-manager` |
| More than one of the above, or a suite-wide audit | `necturalabs:test-manager` |

Prefer **narrow** integration tests: our code plus one real collaborator. Standing up several live
services at once is a broad integration test — it carries end-to-end costs without end-to-end
coverage, and its failures do not localize.

## House Rules

<HARD-GATE>
1. **Test our code, never a library or framework.** Assume third-party code works — the driver, the
   ORM, the HTTP client. If a test would fail when a dependency changes its output while our code is
   unchanged, it is testing the dependency. What is under test here is our query, our mapping, our
   error translation, our transaction boundary. Wrap the dependency and test our wrapper's behavior
   instead.
2. **Never assert on human-readable copy.** Marketing sentences, labels, error prose, formatted
   dates, currency strings, and whole rendered or serialized documents change for non-behavioral
   reasons. Assert roles, ids and `data-*` attributes, element counts, status codes, error codes and
   types, and state. When the copy genuinely IS the requirement — a legal disclaimer, a regulated
   notice, a wire-protocol constant — assert the identifier the application renders it from (the
   message key, id, or code), never a duplicated literal sentence.
3. **Every new test must be observed failing** for the reason it claims before it counts as passing.
4. **Never weaken a test to get green.** Not by relaxing an assertion, widening a tolerance,
   marking `skip`/`only`/`xfail`, or deleting it. A failing test means the code is wrong (fix the
   code) or the requirement changed (see the upsert matrix below).
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
7. **Never assert on the text of a generated query, the exact arguments of a driver call, or the
   sequence of calls into a client library.** Those assert how the result was phrased, not what the
   system does. They pass when the query is wrong and fail when the query is improved. This is the
   rule that defines this level — see below for what to do when a real collaborator is unavailable.
</HARD-GATE>

## When a Real Collaborator Is Unavailable

<HARD-GATE>
Assert what the collaborator did: the rows that came back, the rows now in the table, the status
code and body fields, the message on the queue, the file on disk.

If a real collaborator is genuinely unavailable, the honest options are, in order:

1. Make one available — Testcontainers, an embedded server, a local instance in CI.
2. Split the work: cover the pure mapping and branching as unit tests, and record the query itself
   as uncovered until a real dependency exists. **Record it in the test file**, naming the specific
   behaviors nothing now covers — ordering, locking, constraint enforcement, dialect-specific SQL.
   A substitute that quietly drops a behavior reads to the next person as coverage.
3. Use a verified fake maintained by the dependency's authors, and treat its fidelity as a risk you
   have named.

Writing SQL-string assertions against a hand-rolled fake is not a fourth option. It produces a green
suite that proves nothing.
</HARD-GATE>

## Workflow

1. **Discover the project's integration setup** — where these tests live, how they are separated
   from unit tests (a distinct directory, a marker, a Failsafe/`*IT` naming rule), how dependencies
   are started, and the exact command that runs this level alone.
2. **Choose the system under test and say what it is.** Which of our processes are real, which
   collaborators are real, which are doubled. Name the hermeticity and fidelity trade-off you made.
3. **Decide add / update / leave** using the upsert matrix below.
4. **Set up data explicitly per test.** See `references/integration-test-rules.md`.
5. **Write the test**, assert on observable outcomes, and **observe it fail**.
6. **Run this level's command**, then re-run anything you touched at least three consecutive times —
   five if it was ever flaky — and report the count. This level is where flakes breed.
7. **Triage anything else the run surfaced** under House Rule 6, classifying each defect
   against `../test-manager/references/test-taxonomy.md` — flaky, skipped, assertion-free,
   unfailable, tautological, copy-asserting, library-testing, change-detector, duplicated,
   obsolete, mislabeled, excessive setup.

### When dispatched by `necturalabs:test-manager`

- Run only your level's command, never the full suite.
- Do not edit shared fixtures, factories, `conftest.py`, or any helper file outside your assigned
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

Full rules with sources: `references/integration-test-rules.md`

| Concern | Rule |
|---------|------|
| Real vs substitute | Real dependency in a throwaway container beats an in-memory substitute. H2 standing in for Postgres passes queries that production rejects. |
| Scope | One real collaborator per test. Broad multi-service tests belong to E2E or nowhere. |
| Data | Each test creates the data it needs and never depends on a seeded snapshot or on another test. Rebuild state *before* the test rather than cleaning up after it; per-test transaction rollback is a separate isolation strategy, not a substitute for that. |
| Isolation | Unique keys per test, or a per-test schema/database/namespace. Two tests sharing a row is a flake with a delay fuse. |
| Readiness | Wait on a readiness condition, never a fixed sleep. |
| Network | Intercept at the network layer with a request-handler library; do not stub the HTTP client's methods. |
| Third-party APIs | Never call a live external service. Use a double plus a contract test to keep the double honest. |
| Time and randomness | Injected and controlled, exactly as in unit tests. |
| Transactions | Test the boundary deliberately: commit, rollback on error, and behavior under a constraint violation. |
| Failure messages | A failure must say which collaborator, which operation, and what differed. |

## Rationalizations — All Rejected

| Excuse | Reality |
|--------|---------|
| "No Docker in CI, so I mocked the driver and asserted the SQL" | That test cannot detect a wrong query. Get a real dependency or record the gap. |
| "Asserting the WHERE clause proves the filter works" | It proves the string was built. Insert non-matching rows and assert they are absent. |
| "The reviewer asked me to assert the ORDER BY clause" | Insert rows out of order and assert the returned order. That is the behavior. |
| "An in-memory DB is close enough" | Dialect differences are exactly what this level exists to catch. |
| "Shared staging data makes setup faster" | It makes failures unreproducible and couples every test to every other. |
| "The test is flaky because CI is slow" | It is flaky because it waits on a fixed timer. Poll for readiness. |
| "I'll seed the fixture once for the whole suite" | Then test order determines results. Seed per test. |
| "Hitting the real third-party sandbox is more realistic" | And makes your suite fail when their sandbox does. Double it and contract-test it. |

## Red Flags — Stop

- An assertion containing SQL, a URL path built by the code under test, or a serialized payload
- A hand-rolled fake of a database driver or HTTP client with assertions on its recorded calls
- A substitute standing in for a real dependency with no note saying which behaviors are now
  uncovered
- `sleep` anywhere in setup or teardown
- Data created in one test and read in another
- A test that passes locally only because of leftover rows
- Cleanup that runs only in an `after` hook

## When Done

Report the system under test you chose and why, what you added, updated, and deleted with reasons,
the failing observation for each new test, the exact command and its output, repeat-run counts for
anything touched, and every defect triaged.

If you are running as a subagent dispatched by `necturalabs:test-manager`, stop here and report
back — it runs the full suite and the review once, over everything. Otherwise, including when
test-manager invoked this skill inline in your own context, run the full suite yourself and then
`necturalabs:iterative-code-review` over the changes — preceded by
`necturalabs:iterative-security-audit` when the changes fall in that skill's trigger list (see its
description; it is broader than auth and crypto), since it chains into the review. That run satisfies the orchestrator's completion
gate rather than adding a second one. If the review returns test findings, fix them here
under these rules rather than re-entering a test skill, so the review runs once per invocation
chain.
