# Skill design

How to decide where a piece of knowledge belongs, and how to write the skill if that is the answer.

## Where does it go?

Ask in this order and stop at the first yes.

| Question | Destination |
|---|---|
| Would its absence make a current frontier agent decide materially worse on *most* tasks? | `AGENTS.md` |
| Is it a recurring procedure with a sharp trigger, needed on a minority of tasks? | a skill |
| Is it detail only one mode of that skill needs? | that skill's `references/` |
| Is it a fact about *this* project rather than a portable practice? | the project's code, config, `ARCHITECTURE.md`, an ADR, a runbook |
| Can a script, linter, type checker, test or CI job decide it? | `scripts/`, `tests/`, CI |
| None of the above | nothing — leave it out |

The last row is the one most often skipped. Guidance that restates what the model already does
reliably is not free: it costs context on every task, dilutes the rules that matter, and has to be
maintained. The test is not "is this true?" but:

> If this rule disappeared, would current agents get it wrong often enough to justify paying for it
> repeatedly?

If the answer is no, delete it. If the answer is "only in one narrow situation", that is a skill or
a reference, not a persistent rule.

Do not weaken a rule that prevents a real safety or correctness failure merely because it costs
tokens. The two failure modes are not symmetric.

## Writing the description

The `description` is routing logic, not marketing. It is the only part of a skill in context at all
times, and it is what decides whether the skill fires.

A good description states **what the skill does**, **when to use it**, and **what it is not for**.
That last clause is what keeps neighbouring skills apart.

Bad — fires on everything:

> Use whenever coding, reviewing, debugging, testing, or working with software.

Good — a boundary a model can act on:

> Independently review a finished non-trivial code change for correctness, design, compatibility and
> test gaps before it is committed or merged. Use when a behavioral, cross-file, schema, dependency
> or concurrency diff is complete and needs a reviewer that did not write it. Not for a typo, a
> formatting-only diff, or code that is still being written.

Limits: 1–1024 characters. `name` is 1–64 lowercase alphanumeric-and-hyphen characters, no leading,
trailing or consecutive hyphens, and equal to the directory name.

## Writing SKILL.md

`SKILL.md` is a router and a workflow contract, not a manual. It holds:

- **mode selection** — classify the task, then say which reference to read for that mode;
- **invariants** — the few rules that hold in every mode;
- **high-level process** — the shape of the work, not its every step;
- **output contract** — what the skill is expected to produce;
- **pointers** — to `references/`, `templates/`, `scripts/`.

It does not hold the content of its own references. Under 500 lines, and well under is better.

Write harness-neutral prose. Say "read the file" and "search the repository", not one product's tool
names. Naming tools is what forced the old per-harness mapping tables to exist, and they went stale
immediately. Where behavior genuinely differs between harnesses, put it in a reference and say so
explicitly.

## Writing references

- One level deep from `SKILL.md`. A reference must not send the reader to a further reference inside
  the same skill; a chain means several reads before the agent knows how to act.
- Every reference must be reachable from its `SKILL.md`. The validator treats an unreferenced file
  as a defect, because in a progressive-disclosure design a file nothing points at is pure weight.
- Split by *mode*, not by size. `references/unit.md` is a useful split because a task is about unit
  tests or it is not. `references/part-2.md` is not.

## Writing scripts

A skill ships a script only when the work is genuinely deterministic. It must have clear inputs and
outputs, predictable failure, no destructive default, and minimal dependencies. Do not hide a
reasoning workflow inside a script to make it look deterministic — that produces a script that is
wrong in ways nobody can see.

## Evals

Every skill carries five cases under `evals/`, named `<skill>-explicit`, `-implicit`, `-contextual`,
`-negative` and `-ambiguous`:

1. **explicit** — the user names the skill or its job directly.
2. **implicit** — a natural request that should route there without naming it.
3. **contextual** — a realistic task where the trigger is embedded in other work.
4. **negative** — a close neighbour that must *not* fire the skill. This is the case that catches an
   over-broad description, and it is the one worth the most.
5. **ambiguous** — a genuinely borderline request; the assertion is that the behavior is
   proportional, not that a particular skill fires.

Each case is a directory holding `prompt.md` and a `graders/` directory. Routing is asserted with a
`tool_used` grader on the `Skill` tool, matching the skill name; a forbidden skill is the same
grader with `min: 0` and `max: 0`.

Run them with `claude plugin eval .`. This spends tokens and needs credentials, so CI validates that
the case files exist and parse, and never executes them. Check that the intended skill fired, that
no unrelated skill did, that only the needed references were read, and that the amount of
orchestration matched the size of the task.

Do not build an elaborate eval platform before these cases work.

## Adding or removing a skill

Adding a skill is a `minor` version bump and needs agreement first — every skill's metadata is a
permanent context cost for every user, so a sixth skill has to be worth more than the routing
ambiguity it introduces with the existing five. Removing one is a `major`.

Before adding, check whether the job is really a new mode of an existing skill. Splitting one skill
into two is justified only when routing evidence shows the single router picking wrong.
