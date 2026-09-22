# Topology

Derive the shape from real data dependencies, never from the order the work was described in.
Pick the smallest shape that expresses them.

| Shape | Use when |
|---|---|
| **One node** | The work is trivial or genuinely sequential. Usually this means no delegation at all. |
| **Fan-out** | The pieces are independent and can run side by side. |
| **Split / work / merge (diamond)** | Independent branches must be recombined into one result. |
| **Pipeline** | Downstream can start on each item as it arrives and never needs the complete upstream set. |
| **Conditional routing** | The work genuinely branches on a result. |
| **Bounded cycle** | Convergence needs more than one round. |

## Edges and barriers

- An edge exists only where a node consumes an upstream result. "Runs afterwards" is not a
  dependency.
- A barrier — waiting for every upstream node before any downstream one starts — is justified only
  when the next stage truly needs the whole upstream set: a synthesis, a deduplication across all
  results, a whole-set validation. A barrier placed out of habit turns a pipeline into dead
  wall-clock.
- Where each item can flow onward on its own, pipeline it: the verification of branch A starts the
  moment A lands, while B is still running.

## Width

Width answers to the same test as delegation itself. Fan out only where the branches are genuinely
independent and the latency or coverage is worth the extra context each branch costs. If one node
would do, use one.

- Two nodes mapping the same subsystem in parallel is duplicated work, not coverage — unless it is a
  deliberately independent review or competing approaches the user asked for.
- Read-only fan-out may go wider than write work, because readers cannot collide.
- Writers need disjoint boundaries before they need parallelism. If the boundaries cannot be made
  disjoint, give each writer its own worktree or serialize them.

## Cycles

A cycle declares, before it starts:

- its **convergence condition** — the observable state that ends it;
- its **hard bound** — the maximum number of rounds, fixed now, not raised mid-run;
- its **deduplication** — every candidate is checked against everything already seen, accepted and
  rejected alike, so a rejected idea cannot return under new wording.

On hitting the bound, stop and report what is unresolved. "One more round" is how a bounded cycle
becomes an open loop.

## Scripted workflows

A script-held workflow chooses its own bounded concurrency, but only after the user has opted in to
one. It keeps intermediate plumbing deterministic: schema validation on every edge, gates and retries
in the script, a verifier node where a check needs judgment. Do not route every intermediate result
back through the manager — the manager takes the final integration, verification and completion
claim.
