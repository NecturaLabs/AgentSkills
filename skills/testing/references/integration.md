# Integration Tests

Our code against one real out-of-process collaborator. The value of this level is fidelity — proving
the query, the serialization, the migration, the transaction, or the protocol actually works. Every
shortcut that trades fidelity away turns this into a slow unit test with worse failure messages.
Assertion discipline, doubles, and determinism that apply everywhere are in `test-quality.md`.

## Contents

- [Scope: narrow over broad](#scope-narrow-over-broad)
- [Defining the system under test](#defining-the-system-under-test)
- [Real dependencies over substitutes](#real-dependencies-over-substitutes)
- [Test data lifecycle](#test-data-lifecycle)
- [Isolation](#isolation)
- [Network boundaries](#network-boundaries)
- [Transactions, migrations, and constraints](#transactions-migrations-and-constraints)
- [Asynchrony and readiness](#asynchrony-and-readiness)
- [Sources](#sources)

## Scope: narrow over broad

A **narrow** integration test exercises the part of the code that talks to one external service, with
that service real or contract-verified. A **broad** integration test stands up several live services
at once — it carries end-to-end costs without end-to-end coverage, and a failure inside it doesn't
localize to one collaborator. Prefer narrow; push anything that genuinely needs several live services
at once down to a scope where it can be narrowed, or up to a journey test that's honest about being
end to end.

## Defining the system under test

Before writing anything, decide and write down which collaborators are real and which are doubled —
that trade-off shouldn't require reading the setup code to discover. Two properties pull against each
other for anything larger than a unit test:

- **Hermeticity** — how isolated the system under test is from anything outside it. Higher
  hermeticity means fewer cross-test conflicts and no environment reservations.
- **Fidelity** — how closely the setup reflects production.

From most to least hermetic: our process plus one throwaway container (the default for this level);
our process plus an in-process test server (fine when the transport itself is ours); several of our
processes on one machine (only when a genuine cross-process protocol is under test); a shared staging
environment (almost never — contamination makes failures unreproducible). Choose the most hermetic
option that still has the fidelity the behavior needs.

## Real dependencies over substitutes

Use the real dependency in a disposable container rather than an in-memory stand-in. A substitute
accepts queries the real engine rejects and rejects queries it accepts — exactly the class of defect
this level exists to catch. Start the container per test class or suite (not per test — startup is
the expensive part, data reset is cheap), wait on a readiness condition the dependency itself exposes
(a health check, a trivial query) rather than a fixed sleep, and pin the image tag to what production
runs so an upstream release doesn't become an unexplained CI failure.

When no real collaborator can be provided: say so explicitly, cover what remains (pure mapping,
branching) at the unit level, and name the specific behaviors left uncovered — ordering, locking,
constraint enforcement, dialect-specific behavior — in the test file, so the gap is visible to the
next reader instead of read as coverage. Asserting the text of a generated query against a hand-rolled
fake is not a fourth option; it passes when the query is wrong.

## Test data lifecycle

Each test creates the data it needs — setup that reads like the scenario ("two paid orders and one
cancelled order for customer X") is the point, not overhead to hide. Reset by rebuilding *before* the
test rather than cleaning up after it; cleanup that only runs on success leaves the next run poisoned
by whatever an aborted run left behind. Never depend on a shared seeded snapshot for the rows a test
actually asserts on — reference data the system needs to boot (currencies, feature defaults) is fine,
the rows under test are not. Insert negative cases too: a filter test that only inserts matching rows
can't fail.

## Isolation

Pick one and apply it consistently: transaction rollback per test (fastest, but useless for testing
commit behavior itself); truncate-and-reseed per test; a per-test schema, database, or namespace
(needed for parallel execution); or unique keys per test derived from the test name as a cheap
partial isolation. Ordering dependence is the diagnostic — run the level with a randomized order, and
if results change, isolation is broken and every result in that run is suspect.

## Network boundaries

Intercept at the network layer, not at the client object — a request-handler library keeps
serialization, headers, status handling, and retries under test, and the same handlers are reusable
across unit, integration, and browser tests; stubbing the HTTP client's methods skips exactly the
code the test meant to exercise. Never call a live third-party service — it fails the suite for
reasons outside the repo, leaks credentials into CI, and rate-limits at the worst time. When the
request itself is the product (a webhook emitted, a payment charged), assert its semantic fields, not
the whole serialized body. A contract test — where the consumer publishes the interactions it
depends on and the provider verifies it satisfies them — is what makes it safe to replace a
team-owned dependency with a double; skip it for a stable, versioned third-party API with a published
spec instead.

## Transactions, migrations, and constraints

These behaviors are only observable at this level, and are the ones most often skipped:

- Commit and rollback paths, including rollback triggered by a mid-operation exception.
- Unique, foreign-key, and check constraint violations surfacing as the error type the code claims to
  raise.
- Concurrent-update behavior where the code relies on locking or optimistic versioning.
- A migration applying cleanly to a database at the *previous* version, not only to an empty one.
- Connection-pool exhaustion and timeout handling — size pools deliberately small in tests so a leak
  surfaces immediately instead of in production.

## Asynchrony and readiness

Never sleep. Poll for the condition with a timeout, subscribe to the completion event, or use the
framework's awaitability helper — a fixed wait racing a variable delay is the most common flake at
this level. Give a timeout its own distinct failure so "the condition never became true" reads
differently from "the assertion failed." Make production timeouts configurable and shorten them for
tests, rather than lengthening the test's patience.

A failure at this level should say which collaborator, which operation, and what differed — "expected
10 orders, got 1" beats "assertion failed" — because a debugging session shouldn't be required just
to read the failure.

## Sources

- *Software Engineering at Google*, ch. 14 *Larger Testing* — https://abseil.io/resources/swe-book/html/ch14.html
- Martin Fowler, *IntegrationTest*, *Testing Strategies in a Microservice Architecture* — https://martinfowler.com/bliki/IntegrationTest.html
- Testcontainers, *Introducing Testcontainers* — https://testcontainers.com/guides/introducing-testcontainers/
- Mock Service Worker philosophy — https://mswjs.io/docs/philosophy
- Pact, consumer-driven contract testing — https://docs.pact.io/
