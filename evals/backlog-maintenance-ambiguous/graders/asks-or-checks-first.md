---
type: llm
weight: 1
---

The user asks to keep track of remaining work, with no tracker or project named. The assertion is proportion, not that any particular skill fires.

PASS if the response checks the repository for an existing tracker or backlog (issue tracker remote, a task file) or asks where the work should be tracked, before creating anything.

FAIL if it invents a task list in a new file or files issues without checking what the project already uses.
