---
name: agent-orchestration
description: Decide whether to delegate work to subagents or a scripted workflow, and run the delegation well — topology from real data dependencies, fan-out width, minimal context packets, disjoint write ownership, model and effort per node, monitoring, failure handling and handoff validation. Use when a task is about to be split across subagents, parallel workers or a workflow graph, or when a running delegation needs steering. Not for work done directly in one session, and not for reviewing a finished change.
---

# Agent orchestration

The session that owns the task is the manager. It owns decomposition, topology, allocation,
integration, final verification and all communication with the user. Delegated agents are nodes:
bounded work with an explicit input and an explicit output. This skill decides *whether* to
delegate, *what shape* the work takes, and *what each node receives*. It does not choose an API —
use whatever delegation, subagent or workflow mechanism the harness itself provides.

## First, the decision

Delegation is a tool, not a default. A node must buy at least one of:

- **parallelism** — independent work finishing sooner side by side;
- **independent judgment** — a reviewer or adjudicator that must not share the author's context;
- **specialization** — a capability, tier or configuration the manager does not have;
- **context isolation** — a large read whose raw output would crowd out the manager's context.

If it buys none of these, do the work directly. Size is not a reason: a single-threaded task handed
to one subagent is the manager's own work plus a briefing, a handoff and a validation. An explicit
instruction from the user not to delegate ends the question.

A harness capability that already runs in its own context — a native review command, a built-in
research agent — is a node in its own right. Prefer it to a hand-briefed subagent doing the same job
when it fits, and brief it with the same discipline.

## Invariants

These hold for every delegation, whichever reference is loaded.

1. **Dependencies come from data, not from the order things were mentioned.** An edge exists only
   where a node consumes an upstream result.
2. **Concurrent writers never interfere.** Each writing node gets a disjoint writable boundary as an
   absolute path, and its own worktree whenever scopes could overlap, a formatter, codegen or test
   run may touch shared files, or disjointness cannot be guaranteed. One owner per writable file at
   a time. An investigation node is read-only.
3. **Stay inside the concurrency cap** the user's instructions set — nested agents included — and
   use 5 active subagents if none is set. A node asks before spawning its own. Read-only fan-out
   may go wider than write work.
4. **A scripted workflow needs the user's explicit opt-in.** Without one, propose it with its rough
   width, loop bound and cost instead of launching it. Fix width and bounds before the run, and do
   not open a second fan-out beside a running one.
5. **Independent judgment gets evidence, never verdicts.** A reviewer, adjudicator or competing
   approach receives the facts and none of another agent's conclusions about them.
6. **Deterministic plumbing never costs a model call** — flattening, filtering, deduplication,
   sorting, routing on known fields, counters, retry and round bookkeeping belong in a script or
   in the manager.
7. **Never duplicate work** except as a deliberately independent review or competing approaches the
   user asked for.
8. **The manager owns the completion claim.** Final integration and verification are never
   delegated away, and a graph with an unfinished path is never reported as complete.

## Process

| Step | Do | Read |
|---|---|---|
| 1. Shape | Pick the smallest topology that expresses the real dependencies, and size each fan-out | [references/topology.md](references/topology.md) |
| 2. Brief | Build each node's context packet and brief: persona, mission, inputs, boundary, deliverable, verification duty, tier and effort | [references/nodes.md](references/nodes.md) |
| 3. Run | Monitor on events plus a heartbeat, answer escalations, validate each handoff | [references/context-and-handoffs.md](references/context-and-handoffs.md) |
| 4. Recover | Resolve a failed node against the graph, escalating one step per redispatch | [references/nodes.md](references/nodes.md) |
| 5. Integrate | Merge the results, run the final verification yourself, report what was dropped or blocked | — |

Trivial or well-understood work gets no topology and no ceremony. Load only the reference the
current step needs.

## Monitoring

Completion notifications arrive on their own, so never poll to learn whether a node is done. Check
in on an event — a handoff lands, a node escalates, or a long-running node has been quiet long
enough that stalling or drift is likelier than progress. On top of that, run the same check every 5
minutes while ordinary subagents are active, so a node that went quiet without emitting an event is
still caught; never tighter. A scripted workflow keeps its own deterministic monitoring instead.

At each check weigh progress, blockers, scope adherence, duplicated effort and stale work, then
nudge, redirect, cancel or reassign. Answer an escalation promptly, and answer the same agent rather
than opening a fresh one — a follow-up to an agent that already holds the context beats one that
must rebuild it.

## Output contract

The manager's report to the user states the outcome; what each node produced and how it was
verified; everything dropped, blocked or left unresolved, by name; and the final verification it
ran itself, with the command and what it printed.
