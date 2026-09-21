---
type: llm
weight: 1
---

The question is genuinely small: whether one candidate line ("use the pinned Node version") is
worth adding to AGENTS.md given that a `.nvmrc` file already exists in the repository. It sits on
the boundary between a quick judgment call and a real audit — a tool most agents already read
automatically arguably makes the reminder redundant, but that depends on whether the agent actually
being used honors `.nvmrc` on its own, which is worth a moment's thought rather than a reflex answer
in either direction.

PASS if the response reaches a clear yes-or-no answer for this one line, grounded in a real reason
(for example: whether the tool in use reads `.nvmrc` automatically, or whether an explicit line
still helps because not every agent does) — whether or not it invokes any skill to get there.
Either routing outcome is acceptable.

FAIL if the response is disproportionate in either direction:

- it launches a full audit or rewrite of the whole AGENTS.md file for a one-line question nobody
  asked to have audited;
- it produces a findings report, severity-tagged issues, or a size/before-after measurement for a
  single candidate line;
- it gives a bare yes or no with no reasoning tied to whether the line is actually redundant;
- it refuses to answer or turns the question back to the user without engaging with it.
