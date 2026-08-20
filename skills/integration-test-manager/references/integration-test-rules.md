# Integration Test Authoring Rules

## Contents

- [Defining the system under test](#defining-the-system-under-test)
- [Real dependencies over substitutes](#real-dependencies-over-substitutes)
- [Test data lifecycle](#test-data-lifecycle)
- [Isolation](#isolation)
- [Network boundaries](#network-boundaries)
- [Contract tests](#contract-tests)
- [Transactions, migrations, and constraints](#transactions-migrations-and-constraints)
- [Asynchrony and readiness](#asynchrony-and-readiness)
- [Flake control at this level](#flake-control-at-this-level)
- [Ownership and failure diagnosis](#ownership-and-failure-diagnosis)
- [Sources](#sources)

## Defining the system under test

Before writing anything, state what is real and what is not. Google's framing for anything larger
than a unit test uses two properties that pull against each other:

- **Hermeticity** — how isolated the system under test is from anything outside it. High hermeticity
  removes cross-test conflicts and environment reservations.
- **Fidelity** — how closely it reflects production: same binaries, same configuration, same
  topology.

Common shapes, from most hermetic to least:

| Shape | Fidelity | Use when |
|-------|----------|----------|
| Our process + one throwaway container | good for that collaborator | the default for this level |
| Our process + in-process test server | moderate | HTTP handler tests where the transport is ours |
| Several of our processes on one machine | higher | a genuine cross-process protocol is under test |
| Shared staging environment | highest fidelity, lowest hermeticity | almost never; contamination makes failures unreproducible |

Pick the most hermetic option that can still observe the behavior, and write down the trade-off in
the test or its file header. "Which collaborators are real here?" should never require reading the
setup code.

## Real dependencies over substitutes

Use the real thing in a disposable container. An in-memory substitute standing in for a production
database accepts queries the real engine rejects and rejects queries it accepts — the class of
defect this level exists to catch. Testcontainers-style libraries start the dependency before the
tests, expose a mapped port, and destroy it afterwards regardless of outcome, which also means
parallel pipelines cannot collide.

Lifecycle guidance:

- **Per test class or suite**, not per test — container startup is the expensive part, data reset is
  cheap.
- **Reuse across a local run** is a developer-experience feature; never let it change behavior. A
  test that only passes on a reused container is depending on leftover state.
- **Wait on a readiness condition** the dependency itself exposes — a log line, a health endpoint, a
  successful trivial query — never a fixed sleep.
- **Pin the image tag** to the version production runs. `latest` turns an upstream release into an
  unexplained CI failure.

When no real dependency can be provided, say so explicitly and cover what remains at the unit level.
An assertion on generated query text is not a substitute: it passes when the query is wrong.

## Test data lifecycle

- **Each test creates the data it needs.** Setup that reads like the scenario is the point: "given
  two paid orders and one cancelled order for customer X".
- **Reset by rebuilding before the test, not by cleaning up after it.** Cleanup that only runs on
  success leaves the next run poisoned; a truncate-and-seed at the start is deterministic.
- **Never depend on a shared seeded snapshot** for the rows a test asserts on. Reference data that
  the system needs to boot (currencies, countries, feature defaults) is fine; the rows under test
  are not.
- **Insert negative cases.** A filter test that only inserts matching rows cannot fail. Insert the
  rows that must be excluded and assert their absence.
- **Prefer building data through your own repository or factory**, not raw SQL, so the test breaks
  when the schema changes in a way the code cannot handle.

## Isolation

Choose one and apply it consistently:

- **Transaction rollback per test** — fastest, and correct when the code under test does not manage
  its own transactions. Useless for testing commit behavior.
- **Truncate and re-seed per test** — simple, works with any transaction usage.
- **Per-test schema, database, or namespace** — needed for parallel execution.
- **Unique keys per test** — cheapest partial isolation: derive ids from the test name, never reuse
  a fixed id across tests.

Ordering dependence is the diagnostic: run the level with a randomized order. If results change,
isolation is broken and every result in that suite is suspect.

## Network boundaries

- **Intercept at the network layer**, not at the client object. A request-handler library that
  intercepts real requests keeps the code path — serialization, headers, status handling, retries —
  under test, and the same handlers can be reused by unit, integration, and browser tests. Stubbing
  the HTTP client's methods skips exactly the code you meant to exercise.
- **Never call a live third-party service.** It makes the suite fail for reasons outside the repo,
  leaks credentials into CI, and rate-limits at the worst time.
- **Assert on the outcome, not the request.** When the request itself is the product — a webhook we
  emit, a payment we charge — assert on the semantic fields, never on the whole serialized body.
- **Record/replay fixtures** are acceptable when regenerated on a schedule and reviewed as code. A
  stale cassette is a green test for a broken integration.

## Contract tests

A narrow integration test proves our side works against *our understanding* of the collaborator. A
contract test proves that understanding matches reality: the consumer publishes the interactions it
depends on, and the provider verifies it satisfies them, each in its own pipeline. This is what makes
it safe to replace a live dependency with a double. Introduce contract tests when a double stands in
for a service owned by another team; skip them when the double stands in for a stable, versioned
third-party API with a published spec you can validate against instead.

## Transactions, migrations, and constraints

These are behaviors only this level can observe, and they are frequently untested:

- Commit and rollback paths, including rollback triggered by an exception mid-operation.
- Unique, foreign-key, and check constraint violations surfacing as the error type our code claims
  to raise.
- Concurrent update behavior where the code relies on locking or optimistic versioning.
- Migrations applying cleanly to a database at the previous version, not only to an empty one.
- Connection pool exhaustion and timeout handling — Fowler's advice is to size pools deliberately
  small in tests so leaks surface immediately instead of in production.

## Asynchrony and readiness

- **Never sleep.** Poll for the condition with a timeout, subscribe to the completion event, or use
  the framework's awaitability helper. A fixed wait racing a variable delay is the most common flake
  at this level.
- **Give the timeout a distinct failure type** so "the condition never became true" is
  distinguishable from "the assertion failed".
- **Make production timeouts configurable** and shorten them in tests rather than lengthening the
  test's patience.

## Flake control at this level

Google's position is blunt: a consistently failing test is better than a flaky one, because
flakiness destroys trust in every other result. Minimize scope, remove sleeps, tune internal
timeouts, and prefer event subscription over polling where the system offers it. Quarantine is a
last resort with an expiry, not a resting place — and a quarantined test still belongs to whoever
put it there.

## Ownership and failure diagnosis

A larger test that fails must say what happened without a debugging session. Two requirements:

- **The failure message names the collaborator, the operation, and the difference.** "Expected 10
  orders, got 1" beats "assertion failed".
- **The test has a documented owner.** Tests without owners rot; at this level, the owner is the
  team that owns the code path, not whoever last touched the file.

## Sources

- *Software Engineering at Google*, ch. 14 *Larger Testing* — https://abseil.io/resources/swe-book/html/ch14.html
- *Software Engineering at Google*, ch. 13 *Test Doubles* — https://abseil.io/resources/swe-book/html/ch13.html
- Martin Fowler, *IntegrationTest* (narrow vs broad) — https://martinfowler.com/bliki/IntegrationTest.html
- Martin Fowler, *Testing Strategies in a Microservice Architecture* — https://martinfowler.com/articles/microservice-testing/
- Martin Fowler, *Eradicating Non-Determinism in Tests* — https://martinfowler.com/articles/nonDeterminism.html
- Google Testing Blog, *Change-Detector Tests Considered Harmful* — https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html
- Google Testing Blog, *Flaky Tests at Google and How We Mitigate Them* — https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html
- Testcontainers, *Introducing Testcontainers* — https://testcontainers.com/guides/introducing-testcontainers/
- Mock Service Worker philosophy — https://mswjs.io/docs/philosophy
- Pact, consumer-driven contract testing — https://docs.pact.io/
