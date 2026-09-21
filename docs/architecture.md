# Architecture

AgentSkills is four layers. Each holds one kind of knowledge, and the value of the system comes from
keeping content in the layer that matches its cost profile.

```
AGENTS.md              persistent policy and routing — paid for on every task
   |
skills/*/SKILL.md      conditional procedure — paid for only when the trigger matches
   |   references/     detail — paid for only when the active mode needs it
   |
docs/, code, config    project truth — read when relevant, authoritative at its source
   |
scripts/, tests/, CI   deterministic enforcement — no model call at all
```

The design target is:

> correctness x reliability / (context + token + latency + orchestration cost)

Strong behavior should be cheap, rather than every agent carrying every procedure on every task.

## Why the layers are separate

**AGENTS.md is loaded on every task**, so anything in it is paid for whether or not it is relevant.
It earns its place only if its absence would make a current frontier agent decide materially worse,
often enough to justify the repeated cost. That makes it the right home for scope boundaries,
environment facts that change what a command must look like, correctness and completion invariants,
orchestration principles, essential security boundaries, and routing to everything else. It is the
wrong home for review methodology, testing doctrine, security checklists, per-language examples, and
anything derivable from the code or the tooling.

It is also the **only** persistent instruction layer. A second always-loaded file — `CLAUDE.md`, a
context-loader skill, a session-start hook that reinjects text — does not add guidance, it adds a
copy that drifts. `scripts/validate.sh` fails the build if one reappears.

**Skills are loaded conditionally**, so their cost is the startup metadata plus the activation. A
skill earns its place when the job recurs across projects, needs a substantial checklist or
specialized reasoning, benefits from references, and has a trigger boundary sharp enough that it
will not fire on unrelated work. A skill is not a place to put everything removed from AGENTS.md.

**Repository truth stays at its source.** Architecture facts belong in the code, the manifests, the
tests, `ARCHITECTURE.md`, ADRs and runbooks. Copying them into a global skill to save one read makes
the copy authoritative-looking and wrong within a release.

**Deterministic work never reaches a model.** Structure validation, link checking, name and version
consistency, inventory and install state are code. A model asked to do them is slower, costlier and
less reliable than a script that cannot forget.

## Progressive disclosure

Three tiers, and the discipline is real:

1. **Metadata** — `name` and `description` only, in context for every skill at all times. This is
   the routing surface and the permanent cost of owning a skill.
2. **SKILL.md** — loaded when the skill activates. A router and workflow contract: mode selection,
   invariants, high-level process, output contract, pointers. Under 500 lines.
3. **References** — loaded only when the selected mode needs them. One level deep from `SKILL.md`;
   no reference chains, because a chain means several reads before the agent knows how to operate.

Solving AGENTS.md bloat by writing a bloated `SKILL.md` moves the cost rather than removing it. The
validator enforces the 500-line ceiling and fails on reference files nothing points at.

## One canonical source, two harnesses

The git checkout is the only editable copy of skill content. `scripts/install.sh` creates a symlink
per skill into each harness's personal skill directory:

```
<checkout>/skills/testing
        |                \
        |                 ~/.claude/skills/testing        (Claude Code)
        \________________ ~/.codex/skills/testing         (Codex)
```

Both products document following symlinked skill directories, and both read `SKILL.md` from the
target. Editing the checkout changes what both harnesses load, with no copy step and nothing to
drift.

To stay loadable by both, `SKILL.md` frontmatter carries only the six keys the open Agent Skills
specification defines: `name`, `description`, `license`, `compatibility`, `metadata`,
`allowed-tools`. Claude-Code-only keys are rejected outright by the Skills API and undocumented for
Codex, so the validator fails on any key outside the six. For the same reason skill bodies are
written harness-neutral — they name capabilities, not one product's tool names.

## Instruction-file loading

The two harnesses discover `AGENTS.md` differently, and both behaviors matter when installing.

- **Claude Code** (verified on 2.1.278) reads `AGENTS.md` natively, but at project level only when
  no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists at or above the working
  directory, so removing those files is what switches a repository to native loading. The behavior
  is controlled by the `instructionFiles` setting, and availability is additionally gated by a
  remote feature flag that defaults to off in the binary — on an account where it is off, deleting
  a project `CLAUDE.md` leaves the repository with **no** instruction file at all. Confirm loading
  before relying on it; `docs/installation.md` gives the details and `scripts/doctor.sh` reports
  them.
- **Codex** reads `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) through its own code path,
  and separately discovers project-level `AGENTS.override.md`, then `AGENTS.md`, then configured
  fallback filenames by walking up from the working directory. `project_doc_max_bytes` (default
  **32 KiB**) is consumed cumulatively across the documents found in that walk only; a document
  that would exceed the running total is truncated **silently**. The global file does not consume
  that budget, so a large global instruction file does not reduce what projects may load — but
  silent truncation within the project chain is indistinguishable from a rule the agent chose to
  ignore, so keep project files lean.

`scripts/doctor.sh` reports both, including the byte size of the resolved global file against the
Codex budget.

## Orchestration is not a layer

Subagents and workflow graphs execute work across these layers; they are not a fifth knowledge
store. A skill is a node capability. Which topology runs, how many nodes, and what context each one
receives is the caller's decision, and belongs in the caller's `AGENTS.md` — not here.
