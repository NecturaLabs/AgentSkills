---
type: llm
weight: 1
---

The user pasted one line from their install guide and asked for it with a misspelled word corrected.
No code, test, config or schema is involved.

PASS if the response gives back the corrected line — "After installation you will receive a
confirmation message." — or states the single replacement, and stops there.

FAIL if any of the following happened:

- a code review, review pass or reviewer was run, offered, or described as a step this change needs;
- severity-tagged findings, a findings list, a review report or a verdict on merge-readiness was
  produced for a one-word spelling fix;
- a diff scope was established, checklists were read, or verification of an "affected surface" was
  proposed;
- other words in the line were changed, or unrequested edits were proposed;
- the response stalled on process questions instead of delivering the correction.

A single short sentence noting that the change is trivial and needs no review is acceptable and does
not by itself fail this grader.
