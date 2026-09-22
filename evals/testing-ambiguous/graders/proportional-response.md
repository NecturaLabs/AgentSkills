---
type: llm
weight: 1
---

The request ("make sure it's solid" before shipping a merged change) is genuinely ambiguous between a
quick review of what already exists and testing work in scope for the testing skill. The code and its
one test are pasted; the run has read-only tools, so nothing can be executed or written.

PASS if the response's scope is proportional to that one change: it examines the retry and backoff
logic against its existing test and names the specific coverage gaps that matter here — for example
the 30-second cap, the exhausted-attempts result, non-retryable results returning immediately, or
the real `sleep` making `chargeWithRetry` hard to test without an injected clock — proposing or
sketching a small number of targeted tests for them.

FAIL if the response gives a generic unsupported reassurance, ignores the pasted code, or performs
work wildly disproportionate to a one-off pre-ship check on one piece of logic (for example auditing
or rewriting a whole test suite, or proposing tests for unrelated parts of the codebase).
