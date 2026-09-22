# Context and handoffs

Discover once where discovery overlaps, reuse facts freely, keep conclusions away from any node
whose job is to judge independently, and widen context only on demand.

## The context packet

The smallest sufficient packet is, at most:

- the objective and its acceptance criteria;
- the relevant files and symbols;
- the architecture, call-graph and data-flow facts the node would otherwise rediscover;
- the contracts, tests and constraints that bind it;
- the upstream output it actually consumes;
- its writable boundary.

Anything beyond that is cost without capability. Every node starts on the smallest plausibly
sufficient context and widens by targeted lookup — never tell a node to "understand the repository
first". Synthesis, reduce and whole-set validation nodes are the exception: they may receive the
complete relevant upstream set.

## Discovery

- Make discovery its own upstream node only when several downstream nodes need substantially the
  same discovery. Where their needs barely overlap, each investigates its own.
- Compile shared context by the cheapest sufficient means: deterministic tool output, then code
  intelligence, then targeted reads, then a cheap agent, and a strong model only where the judgment
  is genuinely hard.

## Citing, not copying

- Context cites: paths, symbols, line ranges, test names, one-line facts. A small exact fact,
  contract fragment or short excerpt is fine where it is cheaper than several nodes retrieving it
  again. Never paste a large source block or a whole upstream conversation.
- Context is a cache. The repository, the requirements and what verification prints are the
  authority. When a node invalidates a recorded fact, correct or drop it before a dependent node
  runs; never keep a stale fact to save tokens.
- Prefer a delta to a regenerated summary. Restating what has not changed costs tokens on every hop
  and is how a summary quietly drifts from the tree it describes.

## Reuse

- Reuse facts freely. Never reuse another agent's conclusions where independent judgment is the
  point: a reviewer, an adjudicator and a competing approach each need the evidence and none of the
  verdict.
- Reuse an existing agent when independence is unnecessary and it already holds the right context.
  A fresh agent earns its startup cost on the same test as any other node.

## Handoffs

A handoff reports:

- the outcome, files touched and findings;
- the verification it ran, with the output;
- blockers and remaining work;
- separately, what is **new**: facts learned, assumptions changed, dependencies discovered,
  uncertainty left.

Under ordinary dispatch the manager validates each handoff against its brief before anything
downstream consumes it: was the deliverable produced, inside the boundary, with the verification
actually run? In a scripted workflow, intermediate edges are validated by schema, deterministic
checks, gates or an explicit verifier node instead.
