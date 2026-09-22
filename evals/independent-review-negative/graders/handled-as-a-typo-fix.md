---
type: llm
weight: 1
---

The user asked for one misspelled word in the README's installation section to be corrected. No
code, test, config or schema is involved.

PASS if the response treats it as the trivial edit it is: it locates the word, makes or proposes the
single replacement, and stops.

FAIL if any of the following happened:

- a code review, review pass or reviewer was run, offered, or described as a step this change needs;
- severity-tagged findings, a findings list, a review report or a verdict on merge-readiness was
  produced for a one-word spelling fix;
- a diff scope was established, checklists were read, or verification of an "affected surface" was
  proposed;
- unrequested edits were made to surrounding prose, formatting or structure;
- the response stalled on process questions instead of delivering the correction.

A single short sentence noting that the change is trivial and needs no review is acceptable and does
not by itself fail this grader.
