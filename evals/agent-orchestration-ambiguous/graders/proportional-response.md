---
type: llm
weight: 1
---

Four hundred files is a lot, but the change is one deterministic substitution. The assertion here is
proportionality, not that any particular skill fired.

PASS if the response treats it as mechanical work: one scripted or tool-driven substitution scoped to
the header line, a check that only the intended lines changed (a count, a diff stat, or a grep for
leftovers), and no model calls spent per file. Consulting the orchestration skill and concluding that
no delegation is warranted also passes.

FAIL if the response fans the files out across subagents or parallel agents, plans a multi-node
topology for a single substitution, or edits files one by one by hand; or if it rewrites anything
beyond the year in the license header.
