---
type: llm
weight: 1
---

The user made a small, easily reversible config change (a connection-pool size) and asked whether it
is worth writing up. This is a genuinely borderline case: it is a real tuning decision with a
rationale, but it is cheap to reverse and has no real "alternatives considered" story — the kind of
change the project-docs skill's own guidance says does not earn a full ADR. The assertion here is
proportionality, not that any particular skill fires.

PASS if the response is sized to the change. Proportionate handling means it does not manufacture a
heavyweight process for a one-line, reversible config tweak — for example, it says plainly that this
does not need a standalone ADR (because it's small and easily reversed), and either suggests a short
note (a comment, a one-line changelog entry, a line in an existing doc) as enough, or directly says
no write-up is needed beyond the commit message. It should engage with why this does or doesn't
clear the bar, not just assert an answer.

FAIL if the response is disproportionate in either direction:

- it produces or proposes a full ADR, complete with considered-options and consequences sections, for
  a one-line reversible config change;
- it invokes an audit, a documentation tree restructure, or otherwise treats this as bigger than it
  is;
- it dismisses the question with no reasoning at all, giving neither a clear answer nor a rationale
  for why this size of change does or doesn't warrant a record.

Length alone does not decide this — a short, reasoned answer passes; a long one that still ends up
scaffolding a full ADR for a reversible one-liner fails.
