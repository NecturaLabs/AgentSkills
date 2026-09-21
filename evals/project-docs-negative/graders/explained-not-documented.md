---
type: llm
weight: 1
---

The user asked to have the event-stream mechanism explained to them in conversation — "walk me
through" — and named no document, file or lasting artifact.

PASS if the response explains the mechanism directly in the reply (how updates flow from server to
client) and does not create, edit, or propose writing any documentation file (no ADR, architecture
doc, design doc, runbook or reference doc), and does not describe writing one as a next step.

FAIL if any of the following happened:

- a document was created or edited, or the response proposed creating one, as part of answering this
  request;
- the response treated this as a documentation task rather than an explanation, e.g. by describing
  documentation structure, templates, or an audit process instead of explaining the mechanism;
- the mechanism was not actually explained — the response deflected, asked to write it up instead of
  answering, or gave no substantive explanation.

A response that explains the mechanism and, only in passing, notes that this could be written down
if the user wants it later, still passes — offering is not doing.
