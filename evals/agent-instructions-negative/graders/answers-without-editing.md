---
type: llm
weight: 1
---

PASS if the response reports what the pasted file requires before a change is done — passing
`make test` and `make lint` with their output stated, a migration with a tested rollback for schema
changes, an updated changelog entry, and unfinished work listed in the pull request — and neither
edits the file nor proposes a rewrite, audit or restructuring of it.

FAIL if the response audits the file, proposes changes to it, reports on its size, staleness or
structure, or looks for a file on disk instead of answering from the text provided.
