---
type: llm
weight: 1
---

The diff is one changed constant and one new test, but the constant is a default that every caller
of the HTTP client inherits, so the blast radius is larger than the line count. The assertion here
is proportionality, not that any particular skill fired.

PASS if the response is sized to the change and addresses what actually matters for a shared
default: which callers inherit it and whether any of them legitimately need longer, how the new
value interacts with retries or overall deadlines, whether the change is a break for anyone
depending on the old default, and whether the new test was seen failing against the old value.
Either routing outcome is acceptable — a short focused review of that one change, or a direct answer
naming those checks.

FAIL if the response is disproportionate in either direction:

- it runs or proposes a full review apparatus for a one-constant diff: establishing a formal diff
  scope, working through several checklists, producing a severity-tagged findings report, or
  planning fix-and-verify rounds;
- it reads or analyses parts of the repository the change does not reach;
- it waves the change through as trivially safe because it is one line, without touching callers,
  retry or deadline interaction, or the test.

Length alone does not decide this. A short answer that names the real risks passes; a long one that
performs review ceremony without reaching them fails.
