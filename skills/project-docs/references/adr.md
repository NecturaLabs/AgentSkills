# Architecture decision records

An ADR is a short, point-in-time record of one consequential decision, its context, the alternatives
that were weighed, and why the chosen one won. It exists so the next person who wonders "why is it
built this way" does not have to reconstruct the reasoning from a chat log or a departed teammate's
memory.

## Does this decision earn one

Write an ADR when the decision is genuinely consequential *and* hard to reverse — real alternatives
existed, the choice affects the system's architecture or a quality attribute (security, performance,
availability, cost), and undoing it later would be expensive. Signals it clears that bar:

- Changing course later would mean a migration, a breaking change, or redoing meaningful work.
- The decision crosses a module, team or service boundary, so people outside the room that made it
  will be affected by it.
- More than one viable option existed, and picking between them took real judgment, not just
  familiarity.

Do not write one for a decision that is trivial, cheap to reverse, already settled by an existing
convention, or a temporary workaround. A parameter tweak with an easy rollback, a naming choice with
no real alternative, or a proof of concept explicitly meant to be thrown away does not earn an ADR;
if it is worth a sentence anywhere, that sentence belongs in the design doc or commit message that
made the change, not in a standalone record. When it is genuinely unclear which side of the line a
decision falls on, a short ADR costs little and a missing one for a decision that mattered later
costs a lot more — but that asymmetry is a reason to lean toward writing a brief one, not a license to
write one for everything.

## Structure

- **Title** — the problem being decided, not the solution. "How do clients get real-time updates",
  not "Use SSE".
- **Status** — `proposed`, `accepted`, `deprecated`, or `superseded by <the ADR that replaces it>`.
- **Date** — when the decision was made.
- **Context** — the problem and the constraints that made a decision necessary, in a few sentences.
  Enough for a reader with no history on the project to understand why this needed deciding at all.
- **Considered options** — the real alternatives, including the one not chosen. An ADR with only one
  option listed is not recording a decision, it is recording an announcement.
- **Decision outcome** — which option was chosen and why, stated plainly enough that the reasoning
  survives even if every other section were deleted.
- **Consequences** *(optional)* — what gets easier, what gets harder, and what tradeoff was accepted
  knowingly.
- **Related** *(optional)* — links to ADRs, design docs or issues this one supersedes, is superseded
  by, or depends on.

Skeleton: the ADR template in this skill's `templates/` directory.

## Status lifecycle

```
proposed → accepted → (deprecated | superseded)
```

- **Proposed** — under discussion, not yet acted on.
- **Accepted** — in effect; the system is built on this decision.
- **Deprecated** — no longer followed, with no replacement decision recorded (the thing it decided
  about was removed, not replaced).
- **Superseded** — a later decision replaced this one.

## ADRs are append-only

An accepted ADR is a historical record of what was decided and why, at the time. Do not edit its
Decision Outcome to reflect a later change of mind, and do not delete one because the system moved
on — both destroy the record the ADR exists to keep.

When a decision changes:

1. Write a new ADR for the new decision, following the same process — it earns its place on its own
   merits, including recording why the earlier decision no longer holds.
2. Update the old ADR's status to `superseded by <link to the new ADR>`. Leave its body untouched.
3. Link back from the new ADR to the one it supersedes, so either one found in isolation leads to the
   other.

A `deprecated` ADR follows the same rule: change only the status line and add a short reason, leave
the original context and decision text as written.
