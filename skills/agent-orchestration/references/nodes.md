# Nodes

## The brief

A node's brief carries, and a small mechanical node carries only what bears on it:

- a **persona** suited to the repository and task;
- its **mission** and the one bounded responsibility it owns;
- its **inputs** — its context packet and any upstream output it consumes;
- its **writable boundary** as an absolute path, with everything else read-only — an investigation
  node is read-only outright;
- its **deliverable**, and the schema for it when a script or several nodes consume it; output a
  person reads stays prose;
- its **verification duty** — what it must run and report before handing back;
- its **model tier and effort**.

Name only the specific rules the node must apply. Where the harness already gives subagents the
user's instruction files, do not paste them; where it does not, state what the node needs outright.
Resolve every path to a literal absolute string: a fresh node resolves no placeholder and cannot
follow a path relative to material it never loaded.

## Model and effort

Take the first row that matches. **Strong** is the harness's most capable model and **ordinary** its
standard one; the table is written in tiers because vendor model names change far faster than this
guidance should. Never spend the strong tier on deterministic or low-judgment work.

| Node | Tier | Effort |
|---|---|---|
| Complex work where failure is costly or irreversible: auth, crypto, production data, destructive migrations | strong | highest |
| Architecture, security-sensitive or cross-cutting review, concurrency, hard migrations, multi-system debugging | strong | high |
| Short judgment, little output: review a plan, choose between approaches, adjudicate a finding | strong | medium |
| Debugging one subsystem whose cause is unknown after a first look | ordinary | highest |
| New behavior or a fix across a handful of files of known code; new tests; ordinary diff review; research needing synthesis | ordinary | high |
| Edits in one or two files following an existing pattern; tests mirroring existing ones; docs; context compilation | ordinary | medium |
| Fully specified steps: searches, reading and summarizing named files, renames, listing, counting | ordinary | low |

Every node starts at its own row, not where a previous node ended.

## Escalation

A node escalates at once — rather than guessing — for ambiguity that materially changes the work,
conflicting requirements, missing context, a blocker, or a consequential decision it lacks evidence
for. The manager answers, redirects or reallocates promptly, and is a router for everything else, not
a participant in the node's work.

When a node falls short, escalate one step per redispatch and pass its partial results along:

- raise effort when it ran out of depth;
- switch to the strong tier at high effort when it took a wrong approach or misread the design;
- after the strong tier at its highest effort falls short, stop and report.

## Failure

A failed node is resolved against the graph, not by a blanket rule.

1. Apply its predeclared bounded retry or escalation policy first.
2. A failed **optional or independent** node drops its own branch, and the drop is reported.
3. A failed **required dependency** blocks its downstream descendants, which never run on absent
   input. Branches that do not consume its output continue.
4. If recovery fails, stop the affected integration path and report the blocker.

In a scripted workflow the retry and gating are deterministic and belong to the script; under
ordinary dispatch the manager owns the unresolved branch. Name everything dropped or blocked in the
final report — never present a graph as complete when a path through it did not finish.
