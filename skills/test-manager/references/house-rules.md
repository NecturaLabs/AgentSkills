# House Rules — Canonical Copy

This is the reference copy of the six house rules. They are duplicated in `../SKILL.md`,
`../../unit-test-manager/SKILL.md`, `../../integration-test-manager/SKILL.md` and
`../../e2e-test-manager/SKILL.md`, because an agent that loads only one of those skills must still
see every rule — verbatim apart from clauses a level adds for its own failure modes.
`../../../tests/validate-house-rules.sh` fails the build when a copy drifts.

## What gets duplicated, and what gets a path

- **Duplicated verbatim** — anything an agent must apply *while authoring*: the six house rules and
  the upsert matrix. These bind behavior in the moment; a path the agent may not follow is not
  enough.
- **Referenced by path** — anything an agent *consults*: sourced rule sets, framework conventions,
  the triage catalogue. These are looked up when relevant and cost context when inlined.

Level-specific rules are added as rule 7 and beyond; a level may also insert clauses into rules 1–6
where its own failure modes need naming. Neither may drop, truncate, or invert any of the six.
`../../../tests/validate-house-rules.sh` enforces that both guarded halves of every rule
survive, and `../../../tests/house-rules-guard.sh` proves that check can still fail. An inversion bolted on as an extra
clause — keeping both halves and appending "…but weakening is fine when CI is red" — passes the
script; that one is caught in review.

## The rules

Rule 4's parenthetical points at the upsert matrix, which is inlined in each SKILL.md rather than
here — this file carries the six rules and nothing else, so that a copy of it is never mistaken for
a complete skill.

1. **Test our code, never a library or framework.** Assume third-party code works. If a test would
   fail when a dependency changes its output while our code is unchanged, it is testing the
   dependency. Wrap the dependency and test our wrapper's behavior instead.
2. **Never assert on human-readable copy.** Marketing sentences, labels, error prose, formatted
   dates, currency strings, and whole rendered or serialized documents change for non-behavioral
   reasons. Assert roles, ids and `data-*` attributes, element counts, status codes, error codes and
   types, and state. When the copy genuinely IS the requirement — a legal disclaimer, a regulated
   notice, a wire-protocol constant — assert the identifier the application renders it from (the
   message key, id, or code), never a duplicated literal sentence.
3. **Every new test must be observed failing** for the reason it claims before it counts as passing.
4. **Never weaken a test to get green.** Not by relaxing an assertion, widening a tolerance,
   marking `skip`/`only`/`xfail`, or deleting it. A failing test means the code is wrong (fix the
   code) or the requirement changed (see the upsert matrix below).
5. **Never encode a known bug as expected behavior.** If writing a test reveals a defect, fix the
   defect. A green test that pins a bug in place is worse than no test.
6. **You ran it, you own it.** A test that failed, flaked, or was skipped in a run you performed is
   yours to deal with. The only question is whether you fix it or report it — never whether to
   mention it. Fix it in the current work when it sits in what you changed; fix it in its own commit
   when it is small and self-contained, which a flaky or skipped test almost always is. Report it,
   with file:line and how big the fix looks, when fixing would swamp the intended change, when the
   problem spans the whole suite, or when the failure exposes a bug in untested or legacy code whose
   current behavior may be load-bearing — there, establish coverage before changing what you cannot
   verify. "Different module", "predates my change", "unrelated to this task"
   and "out of scope" are never reasons to stay silent, and rarely reasons not to fix. Dismissing it
   requires establishing it is not a defect, and citing the evidence for that.
