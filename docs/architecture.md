# Architecture

necturalabs-fab is one Rust binary that gives coding agents a stable, machine-readable interface to
the Fab marketplace. It owns the interface and the policy; a replaceable **provider** owns
marketplace access. FabCLI is the current provider and an implementation detail.

```text
Claude Code / Codex / other agents
        │  loads plugin/skills/necturalabs-fab/SKILL.md (installed as a plugin), runs the CLI
        ▼
necturalabs-fab CLI ──────────── src/main.rs, src/cli.rs, src/commands/
  │  config layers            src/config.rs
  │  approval + money gate    src/approval.rs
  │  deterministic ranking    src/rank.rs
  │  envelope / rendering     src/output.rs
  ▼
FabProvider trait ─────────── src/provider/mod.rs   (capabilities, request/receipt types)
  │
  ├── FabCliProvider ──────── src/provider/fabcli/   (subprocess, version gate, JSON mapping)
  │        │ spawns
  │        ▼
  │     fabcli (GPL-3.0, separate process) ──► Epic / Fab undocumented APIs
  │
  └── (future) native provider
```

## Boundaries

| Boundary | Rule | Where enforced |
|---|---|---|
| Agent ↔ CLI | One JSON envelope on stdout, stable `FAB_*` codes and exit codes. Progress and warnings never on stdout. | `src/output.rs`, `src/main.rs`, `src/error.rs` |
| Commands ↔ provider | Commands see only `FabProvider` and the types in `src/model.rs`. Nothing above the provider knows a FabCLI field name. | `src/provider/mod.rs` |
| Provider ↔ FabCLI | FabCLI is executed, never linked. Its output is mapped once, in `map.rs`; unknown shapes become `FAB_PROVIDER_PROTOCOL`, never guessed values. | `src/provider/fabcli/` |
| Money | No code path purchases. Claims re-check the price and fail closed. | `src/approval.rs`, `src/commands/claim.rs` |
| Credentials | necturalabs-fab never reads, stores or forwards a token. Provider stderr is redacted before it is quoted. | `src/sanitize.rs`, `src/provider/fabcli/exec.rs` |

## Data flow for `find`

1. `commands::build_query` turns flags plus config defaults into a validated `SearchQuery`.
2. The provider searches (with ownership decoration when the session allows it) and establishes
   each result's licences from Fab's licence search filter, which FabCLI's listing output lacks.
3. `commands::hydrate` fetches listing detail and formats for the top N results — Fab's search
   index carries no engine, version or technical data.
4. `rank::rank` hard-filters positive incompatibilities, scores the rest from fixed weights, and
   sorts deterministically.
5. The command emits candidates with every signal and reason, plus what was excluded and why.

`search` is steps 1, 2 and optional 3; `recommend` is `find` plus a single labelled pick.

## Normalized model

`src/model.rs` is the contract agents parse. Unknown values are omitted from JSON; each asset's
`coverage` says whether a field group was fetched, skipped, or unavailable, so "no engines" and
"engines never checked" stay distinguishable. Marketplace-authored text passes through
`sanitize::text` (control characters, ANSI and bidi overrides stripped; length capped) because it
is untrusted input that an agent will read.

## Extension points

- **Another provider:** see `docs/providers.md`.
- **Import into an engine:** out of scope by design. A downloaded asset leaves a
  provider-independent `necturalabs-fab.asset.json` sidecar (listing id, title, engine versions,
  platforms) that a future import step can consume without querying the marketplace again.

## Decisions

- `docs/adr/0001-implementation-language.md`
- `docs/adr/0002-marketplace-access-through-fabcli.md`
- `docs/adr/0003-gating-account-and-monetary-actions.md`
