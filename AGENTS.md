# AgentSkills — Agent Guidelines

This repository is a set of Agent Skills for Claude Code and OpenAI Codex, the `necturalabs`
marketplace that pins the third-party plugins the NecturaLabs setup uses, and the `necturalabs-fab`
CLI behind the `fab` skill. The Markdown under `skills/` is the product, not prose about the
product.

## Commands

Run from bash on Linux:

- Full offline suite: `npm test` (equivalently `bash tests/run-all.sh`)
- Structure validation only: `bash scripts/validate.sh --strict`
- Install into this machine's harnesses: `bash scripts/install.sh` (`--dry-run` to preview)
- Report installation health: `bash scripts/doctor.sh`
- Remove this project's links: `bash scripts/uninstall.sh`
- Version agreement (package, plugin, crate; optionally a tag): `sh scripts/check-version.sh [vX.Y.Z]`
- Fab CLI: see `cli/fab/AGENTS.md` (`cargo test` from `cli/fab`)

The suite is entirely offline: every check reads files in this repo. Nothing needs the network, the
`claude` CLI, or credentials, and nothing that does may be added — no API key belongs in this repo
or its CI, so such a check could only ever be skipped, and a permanently skipped check reads as
coverage while providing none.

Two official tools exist alongside the suite and are for humans to run, not CI:

- `claude plugin validate . --strict` — Anthropic's own manifest and frontmatter validator.
- `claude plugin eval .` — runs the routing evals under `evals/`. It spends tokens and needs
  credentials, which is why CI validates the eval *files* and never executes them. Run
  `bash scripts/fetch-eval-plugins.sh` first (it fetches the pinned third-party plugins some cases
  load into the ignored `evals/.plugins/`), then run it once per release and record the result in
  `docs/evals.md`.

## Architecture

Four layers, each with one job. Putting content in the wrong layer is the defect this repository
exists to avoid.

- `AGENTS.md` — persistent instruction and policy. The only such layer. Small.
- `skills/*/SKILL.md` + `references/` — conditional procedure, loaded on demand.
- `docs/`, code, config — authoritative project truth, read when relevant.
- `scripts/`, `tests/`, CI — deterministic enforcement, never a model call.

`cli/fab/` is a Rust crate with its own `AGENTS.md`; its docs are `docs/fab/`. `plugins/` holds
only files of our own: connector manifests whose servers users install from upstream, and a
language-server config. Third-party plugins are marketplace entries pinned to upstream commits in
`.claude-plugin/marketplace.json`; never commit their code here. `setup/` holds the recommended
settings and worker agents the README's setup section merges in.

`examples/` sits outside those layers: finished `AGENTS.md` files shipped for users to copy, not
instructions for work on this repo. They are named `*-agents.md` so an agent working under
`examples/` never loads one as scoped instructions, and `scripts/validate.sh` fails the build if a
file named `AGENTS.md`, `AGENTS.override.md` or `.cursorrules` appears there, or if a required
example goes missing. The root `AGENTS.md` — this file — governs work on AgentSkills itself.

**AGENTS.md is the only maintained policy source here.** No competing CLAUDE policy layer, no
`GEMINI.md`, context loader, or session-start hook that reinjects instruction text. A repository
`CLAUDE.md` is forbidden and `scripts/validate.sh` fails the build if one reappears; the one
verified exception is a user-scope shim outside this repo, covered in `docs/installation.md`.

The checkout is the single canonical source for skill content. `scripts/install.sh` symlinks each
skill into `~/.claude/skills/` and `~/.agents/skills/`; both harnesses follow symlinked skill
directories. Codex also scans `$CODEX_HOME/skills` (default `~/.codex/skills`); install never writes
there, and `doctor.sh` checks it for a shadowing duplicate. Never maintain a copied per-harness
skill body.

## Skill authoring

- Frontmatter carries only the six Agent Skills spec keys: `name`, `description`, `license`,
  `compatibility`, `metadata`, `allowed-tools`. Claude-Code-only keys such as `when_to_use`, `model`,
  `effort` or `context` are hard-rejected by the Skills API and undocumented for Codex; the validator
  fails on any key outside the six.
- `name` is 1–64 lowercase alphanumeric-and-hyphen characters, no leading, trailing or consecutive
  hyphens, and equals the directory name.
- `name` never reuses a harness-native capability's name or alias; `scripts/native-names.tsv` lists
  them and the validator enforces it. Name what the skill adds, not the job a harness already does.
  Refresh the list when a harness release adds bundled skills, following the steps in its header.
- A skill complements a native capability rather than competing with it: where a harness does the
  same job, the skill is the portable procedure around it and the fallback where it is missing.
- `description` is 1–1024 characters and is routing logic: it must make the trigger distinguishable
  from every neighbouring skill, and say what the skill is *not* for.
- `SKILL.md` is a router and workflow contract — mode selection, invariants, process, output
  contract, pointers. Under 500 lines. Detail belongs in `references/`, one level deep, no chains.
- Every reference and template file must be reachable from its `SKILL.md`. Unreferenced files are
  dead weight in a progressive-disclosure design, and the validator treats them as a defect.
- Write harness-neutral prose. Name capabilities ("read the file", "search the repository"), not a
  specific harness's tool names — that is what made the old per-harness mapping tables necessary.
- Every skill carries five eval cases under `evals/`: `<skill>-explicit`, `-implicit`,
  `-contextual`, `-negative`, `-ambiguous`.

## Boundaries

- **Always**: run the suite before claiming done; keep `package.json`,
  `.claude-plugin/plugin.json` and `cli/fab/Cargo.toml` on the same version; keep the skill lists in `scripts/install.sh`,
  `uninstall.sh`, `doctor.sh` and `tests/install-guard.sh` equal to `skills/` (the validator
  checks).
- **Ask first**: adding or removing a skill; changing what `tests/run-all.sh` aggregates.
- **Never**: write anything under `.claude/worktrees/` — sibling branches live there with their own
  uncommitted state, and the shell's working directory persists between commands.
- **Never**: add a check needing the network, credentials, or the `claude` CLI.
- **Never**: let a suite write inside `tests/` or `scripts/`, or depend on another suite having run.
  `run-all.sh` may start them concurrently, so shared state is a race. A suite that needs to write
  builds its own sandbox under `mktemp -d`.

## Versioning

Semver across `package.json`, `.claude-plugin/plugin.json` and `cli/fab/Cargo.toml`, which change
together (a `vX.Y.Z` tag also builds the `necturalabs-fab` release binaries): **patch** for
fixes and typos, **minor** for new skills or features, **major** for removed skills or restructured
layout. Work lands directly on `main`.
