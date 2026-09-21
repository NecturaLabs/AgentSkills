# Document types

Four kinds of document, each answering a different question. Match the kind to the question the
reader actually has, not to what feels thorough to write.

## Architecture overview

**Question it answers:** how is this system put together?

A map of components, boundaries and the data and control flow between them — the shape a new
contributor needs before any of the code will make sense. It names the pieces and how they relate;
it does not restate what each piece does internally. Where the detail already lives clearly in the
code, link to it (a module, a schema, an interface) instead of copying it — a copy is a second place
that same fact can go wrong.

Write one when a system has enough moving parts that "read the code" is no longer a reasonable way
to get oriented — several services, a non-obvious data flow, or boundaries that are not visible from
any single file. A single-module utility does not need one; its own top-level comment or README
paragraph is enough.

**Length:** short enough to read in one sitting — a diagram or two, the components, the flows between
them, and pointers into the code. If it is growing past that, it is turning into a design doc or
several narrower ones; split by boundary, not by adding more depth to one page.

**Update trigger:** a component is added, removed, or a boundary between them moves. Not a calendar.

## Design document

**Question it answers:** what are we building and why this shape, of the alternatives that existed?

Written while a design is being worked out — before a build, or as it evolves during one — and kept
current as the design changes; it is a living document, not a point-in-time record like an ADR.
Cover the problem, the chosen design, the trade-offs that shaped it, and the alternatives that were
seriously considered and why they lost. State goals and explicit non-goals; a non-goal left implicit
gets silently expanded by the next reader.

Write one when there is real uncertainty about the right approach, the design has trade-offs worth
being explicit about, or several components or a cross-cutting concern (security, performance,
compatibility) are involved. A change with one obvious way to do it does not need one.

**Length:** proportional to the design's real complexity — long enough to cover the trade-offs
honestly, short enough that people still read it. A design doc that has grown into an inventory of
every implementation detail has drifted into restating the code; trim it back to the decisions that
mattered.

**Update trigger:** the design changes. Edit in place rather than appending a second version below
the first.

Skeleton: the design-doc template in this skill's `templates/` directory.

## Runbook / how-to

**Question it answers:** what do I do, step by step, to get this specific outcome?

Task-oriented, not explanatory. State the goal, the prerequisites, then numbered steps that work
when followed literally — commands, expected output, what to check if a step fails. Background and
rationale belong in an architecture doc or design doc; link to it rather than re-explaining it here,
so the steps stay skimmable under pressure (most runbooks get read during an incident or a first-time
setup, not for leisure).

Write one for a procedure that recurs, that a new contributor needs and would otherwise have to
reconstruct, or that matters enough during an incident that reconstructing it from memory is the
wrong time to try. A one-off task with no reason to recur does not need one.

**Length:** as short as the real procedure allows. A step a competent operator would already know
does not need spelling out; a step where the wrong choice is costly does.

**Update trigger:** a step stops working, a command's flags change, or the procedure it documents is
replaced. Verify each command in a runbook actually runs as written before trusting it; a runbook
with a broken first step gets abandoned by the second incident.

## Reference documentation

**Question it answers:** what is the exact shape of this — to look up, not to read start to end.

Stable facts a reader consults rather than narrates: a configuration option's name, type, default and
effect; an API's parameters and responses; a data model's fields and constraints. It is organized for
lookup — a table, a per-field list — not as prose with a story arc.

Write one when the facts are stable enough to be worth writing down separately from the code, and
numerous enough that scanning the source for them each time is real friction. Do not duplicate
something already generated from the code (an OpenAPI spec, a generated type reference); reference
docs cover what generation does not produce.

**Length:** as long as the surface it documents, since it is consulted, not read cover to cover — but
nothing in it that a generator could produce instead.

**Update trigger:** the documented shape changes — a field, a parameter, a default. Same commit as
the change, because a reference doc that lies is worse than none; a reader trusts it precisely
because it looks authoritative.
