---
name: testing
description: Write, repair, debug, audit or delete automated tests. Use when adding coverage for new behavior, writing a regression test for a defect, fixing a failing or flaky test, choosing the right test level, or auditing a suite's quality. Not for explaining what an existing test does, and not for running a suite as a routine verification step.
---

# Testing

Owns automated tests as a portfolio: what to add, what to fix, what to delete, and at which level.
The decision that matters most is rarely "how do I write this test" — it's whether the change in
front of you needs a new test, a change to an existing one, or nothing at all.

## Task classification

| Signal | Mode | Done means |
|---|---|---|
| New or changed behavior has no test that observes it | **Author** | The behavior is pinned at the cheapest level that can see it, and the new test has been seen failing for the reason it claims. |
| A defect just got a fix | **Author (regression)** | The test existed and was seen red against the unfixed code before the fix landed. |
| An existing test is wrong on its own terms — flaky, weak, assertion-free, mislabeled, asserting the wrong thing — but the behavior it's supposed to pin down hasn't changed | **Repair** | The defect is named, the fix addresses that defect (not the assertion value), and the repaired test still fails against broken behavior. |
| A test is failing or flaky and the cause isn't known yet | **Debug** | The cause is established — product defect, environment, timing, shared state, test bug — before anything is changed. See `references/test-quality.md` for flake diagnosis. |
| A suite, directory, or feature's coverage needs assessing as a whole | **Audit** | Every test in scope is classified by what it actually does at runtime, defects are catalogued, and the portfolio shape is reported. Scope this to what was actually asked — a fix to one function does not license a walk through the whole suite. |

This skill is not for reading an existing test and explaining what it checks — that's a read, not a
testing task. It is also not for running the suite as a routine step after unrelated work; that
verification belongs to whatever produced the change, not to this skill on its own.

## Choosing the level

Ask what the behavior needs in order to be observed, then use the cheapest level that can actually
see it. Do not default upward because a higher level "feels more real."

| The behavior is observable by | Level | Reference |
|---|---|---|
| Calling the code in one process, no I/O | Unit | `references/unit.md` |
| Only when the code talks to a real out-of-process collaborator — database, HTTP, queue, cache, filesystem | Integration | `references/integration.md` |
| Only when a user drives the assembled system through its real interface | E2E | `references/e2e.md` |

Two traps to check before committing to a level:

- **The wiring itself is a behavior, the parts it wires are not.** "The query returns the right
  rows" is integration; "the totals are computed correctly" is unit, even when the numbers ultimately
  come from that query in production.
- **A journey is not a feature list.** If the instinct to write an e2e test comes from "several units
  changed," that's a bundle of unit tests wearing a costume, not a journey. E2E earns its cost only
  for a flow that's both critical and only observable end to end.

When classifying a test that already exists (debug, repair, or audit), classify by what it does at
runtime, not by which directory or naming convention it lives under — a "unit" test that opens a
socket is an integration test regardless of its folder. `references/test-quality.md` has the
classification and triage tables.

## Deciding whether to touch an existing test

| Change in front of you | Existing tests | New tests |
|---|---|---|
| Pure refactor | Unchanged. If one breaks, either the refactor changed behavior or the test was coupled to implementation — fix that cause, not the assertion. | None |
| New feature | Unchanged | Add, covering the new behavior only |
| Bug fix | Unchanged | Add a regression test, written and seen failing against the unfixed code first |
| Behavior intentionally changed | Update the tests whose asserted behavior is now different | Add for anything genuinely new |

Editing an existing test's expected value to match new output is warranted only when the behavior it
encodes genuinely changed on purpose. Any other edit that makes a test pass is a repair of a defect
in the test itself (see the triage catalogue in `references/test-quality.md`) — name which defect,
confirm the product behavior is correct first, then fix the test so it fails against broken behavior
and passes against the real one. "It was failing" and "it was slow" are not reasons to delete a test;
deletion needs one of: the behavior no longer exists, it duplicates another test at the same level,
it's defective with nothing salvageable, or it's now covered more cheaply by a replacement that was
itself seen failing first.

## Invariants

These hold regardless of mode or level:

- **Test the code you own, not a dependency.** If a test would fail because a library changed its
  output while your code is unchanged, it's testing the library. Wrap the dependency and test the
  wrapper's behavior.
- **Don't assert on copy that exists for humans** — rendered sentences, labels, formatted dates,
  currency strings, whole documents. Assert roles, ids, `data-*` attributes, counts, codes, types,
  and state. Where a specific string genuinely is the requirement (a legal notice, a wire-protocol
  constant), assert the identifier it's rendered from, not the literal text.
- **Be deterministic by construction.** Inject the clock, randomness, and id generation rather than
  asserting against real time or hoping a seed doesn't matter. Never sleep for asynchronous work —
  poll the condition, subscribe to the event, or use the runner's fake timers.
- **A new test earns trust by being seen red first**, for the reason it claims — a regression test
  against the unfixed code, or any other test proven to fail when the behavior it covers breaks. A
  test nobody has watched fail is not yet a test, but this doesn't require a scripted mutate-and-
  restore ritual on every ordinary test — any credible way of seeing it fail for the right reason
  counts.
- **Never make a test pass by weakening it** — relaxing an assertion, widening a tolerance, adding a
  skip or retry, or deleting it without one of the legitimate deletion reasons above. A failing test
  means the code is wrong or the requirement changed; neither is fixed by changing the assertion to
  match bad output.
- **Never encode a known bug as expected behavior.** A test that asserts buggy output is worse than
  no test, because it protects the bug from being fixed.
- **A test you ran is yours to deal with.** A failure, flake, or skip your own run surfaced gets
  fixed if it's small and touches what you're working on, or reported with its location and a size
  estimate if fixing it would swamp the task. "Predates my change" and "different module" are not
  reasons to stay silent about it.

## Output contract

Report, for whatever mode ran:

- What was added, updated, or deleted, and why — citing the upsert decision or the named defect.
- For every new or repaired test, how it was confirmed to fail for the reason it claims.
- The exact command run for the affected level and its actual result — not a description of
  expected output. Quote the output where it shows a failure or something unexpected.
- Any defect the run surfaced that wasn't already in scope: fixed alongside (if small), or reported
  with file and location plus a size estimate.
- For audit mode: the classification of everything reviewed, the defect catalogue, and the portfolio
  shape observed versus the ~70/20/10 unit/integration/e2e default.

## References

- `references/test-quality.md` — behavior vs. implementation, assertion discipline, test doubles,
  determinism, classifying an existing test by runtime behavior, the defect triage catalogue, and
  flake diagnosis.
- `references/unit.md` — unit-level boundaries, structure, and per-ecosystem conventions.
- `references/integration.md` — integration-level boundaries: real collaborators, data lifecycle,
  isolation, and network handling.
- `references/e2e.md` — e2e-level boundaries: when a journey earns this level, locators, waiting,
  and flake control.
