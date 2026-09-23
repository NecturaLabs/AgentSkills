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
the decision whether to delegate at all, essential security boundaries, and routing by requirement
to everything else. It is the wrong home for review methodology, testing doctrine, security
checklists, delegation procedure, per-language examples, and anything derivable from the code or the
tooling. The shipped global example holds to that at about 12 KB.

It is also the only maintained policy source: no competing CLAUDE policy layer, no context-loader
skill, no session-start hook that reinjects text. A repository `CLAUDE.md` is forbidden here — a
second always-loaded file doesn't add guidance, it adds a copy that drifts — and
`scripts/validate.sh` fails the build if one reappears. The one verified exception is a user-scope
shim outside this repo entirely, covered in `docs/installation.md`.

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
        \________________ ~/.agents/skills/testing        (Codex)
```

Both products document following symlinked skill directories, and both read `SKILL.md` from the
target. Editing the checkout changes what both harnesses load, with no copy step and nothing to
drift. Codex also scans `$CODEX_HOME/skills` (default `~/.codex/skills`); install never writes
there. See `docs/installation.md` for the verified skill-root facts.

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

## Native capabilities first

Both harnesses now ship capabilities that overlap these skills: Claude Code bundles `/code-review`
(run in a forked context, from a quick pass up to a multi-agent cloud review) and
`/security-review`, and Codex ships `/review` backed by a `review-agent` system skill. A harness's
own capability is maintained with it and tuned to its models, so where one exists and fits, it does
the job. That sets two rules for this repository:

- **A skill is the procedure around a native capability, and the fallback where none exists.**
  `independent-review` owns scope, the uncontaminated brief, the evidence standard, adjudication and
  the stop rule, and uses the harness's reviewer as its review pass when one runs in a separate
  context. `threat-review` defers to a native security review for what it covers and keeps the
  surfaces it excludes, such as dependency changes. The routing evals accept either route where
  both satisfy the request, and require this plugin's skill only where it alone adds something.
- **No skill takes a native name.** In Claude Code a personal or project skill replaces a bundled
  one of the same name but not its aliases; Codex lists two same-named skills side by side with no
  precedence. Either way the user silently loses the native capability, so the validator fails on
  any name in `scripts/native-names.tsv`. The list is maintained by hand because neither harness
  exposes its bundled names to a script: Claude Code compiles them into the binary under minified
  identifiers that change between releases. `doctor.sh` reads Codex's system skills live from disk
  and checks Claude Code against the list.

Routing belongs to the policy layer, and it routes by requirement. The global example states what
must happen — an independent review, a security pass before it — and lets a native command or a
portable skill satisfy it, instead of naming this plugin's skill as the only acceptable route.

## Orchestration is a skill, not a layer

Subagents and workflow graphs execute work across these layers; they are not a fifth knowledge
store. The decision whether to delegate at all is made on every task, so it stays in `AGENTS.md` as
one rule with the few invariants that must hold before anything else loads. How to delegate —
topology, width, context packets, write ownership, model and effort per node, failure and
escalation — matters only on delegated tasks, so it lives in `agent-orchestration`. The skill names
no harness API: it decides whether and how to delegate, and uses whatever mechanism the harness
provides.
