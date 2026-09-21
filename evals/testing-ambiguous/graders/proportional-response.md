---
type: llm
weight: 1
---

The request ("make sure it's solid" before shipping a merged change) is genuinely ambiguous between
routine verification of what already exists (running the suite, reading the diff) and testing work in
scope for the testing skill (finding and filling a real coverage gap in the retry/backoff logic, or
fixing a weak/flaky test the check surfaces).

PASS if the response's scope is proportional to that one change: it investigates the retry/backoff
logic and its existing coverage, and either runs the relevant tests, points out a specific coverage
gap, or adds/fixes a small number of targeted tests for behavior the merge actually introduced —
without doing nothing at all, and without escalating into a suite-wide audit, a rewrite of unrelated
tests, or authoring tests for unrelated parts of the codebase.

FAIL if the response ignores the request, gives a generic unsupported reassurance with no
investigation, or performs work wildly disproportionate to a one-off pre-ship check on a single piece
of logic (e.g., auditing or rewriting the whole test suite unprompted).
