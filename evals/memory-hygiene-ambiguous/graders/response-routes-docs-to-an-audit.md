---
type: llm
weight: 1
---

The user asks for the project's documentation — a runbook and an architecture page — to be checked
against what is really there. That is a documentation audit, not upkeep of saved memories. The
assertion is the routing and the proportion of the response, not that any particular skill fires.

PASS if the response treats this as a check of the documents against the code and commands (for
example by using the project-docs skill's audit mode, or by describing and starting such a check),
and does not treat it as a cleanup of saved memories or handoff notes.

FAIL if the response turns this into memory upkeep (auditing, merging or deleting saved memories)
instead of checking the documents, or if it neither checks the documents nor says how it will.
