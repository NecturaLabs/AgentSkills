# necturalabs-fab — agent guidelines

Rust 1.85+ CLI (edition 2021) that gives coding agents a stable JSON interface to the Fab
marketplace through a replaceable provider; FabCLI 0.1.x is the current one. Map:
`../../docs/fab/architecture.md`. Part of AgentSkills; the root `AGENTS.md` applies too.

## Commands

- Build: `cargo build`
- Test (offline, no Fab account): `cargo test`
- Single test: `cargo test --test cli_safety claiming_without_approval` or `cargo test --lib rank::`
- Lint: `cargo clippy --all-targets -- -D warnings`
- Format: `cargo fmt` (CI runs `cargo fmt --check`)
- Live read-only check against a signed-in FabCLI: `cargo test --test live -- --ignored`
- Installer round trip in a throwaway HOME (network; downloads FabCLI): `sh ../../scripts/test-fab-installer.sh`
- Version check: `sh ../../scripts/check-version.sh [vX.Y.Z]`. The crate follows the AgentSkills
  version: every release bumps `version` here, in `package.json` and in
  `.claude-plugin/plugin.json` together, and tags `vX.Y.Z` to match.

## Conventions

- The JSON envelope, `FAB_*` error codes, exit codes (`src/error.rs`), flag names (`src/cli.rs`)
  and the asset model (`src/model.rs`) are a public contract agents branch on. Changing or
  removing one is breaking; update `skills/fab/references/` and `docs/fab/` (repository root) in the same change.
- Nothing above `src/provider/` may know a FabCLI field name or flag. Provider payloads are mapped
  once, in `src/provider/fabcli/map.rs`; an unknown value is `None`, never a guess.
- Marketplace-authored strings go through `sanitize::text`/`sanitize::short`; provider stderr
  through `sanitize::redact` before it is quoted anywhere.
- Commands never write to stdout; they return an `Outcome` and `src/main.rs` renders it. Stdout
  carries exactly one JSON document in machine mode.
- The skill is `skills/fab/` in the `necturalabs` plugin, listed as `necturalabs:fab`; there is no
  separate Fab plugin or marketplace.
- `scripts/install-fab.sh` and `scripts/install-fab.ps1` (repository root) are one design in two languages: record every
  artifact in the manifest, and remove exactly the recorded ones on `--uninstall`. Change both.
- The project config layer is untrusted (`src/config.rs`): never let it set a key that chooses what
  runs or what is allowed.
- CLI tests run the real binary against `mock-fabcli` (`src/bin/mock-fabcli.rs`) via
  `tests/support/`. Fixtures in `tests/fixtures/` are hand-written; `<command>-<id>.json`
  overrides `<command>.json` for one listing.

## Boundaries

- **Always**: run the Test and Lint commands before claiming done.
- **Ask first**: widening the supported FabCLI range in `src/provider/fabcli/version.rs` (verify
  the new output against the mapping first); adding a provider operation; any change to the
  approval policy defaults.
- **Never**: add any purchase, checkout or payment capability, flag or config key; read, log or
  forward FabCLI credentials; copy FabCLI or `egs-api-rs` source into this repo
  (`docs/fab/licensing.md`); let a test need the network or a Fab account outside `tests/live.rs`.
- **Never**: run any job on a self-hosted runner; AgentSkills CI triggers on `pull_request`.
- **Security-sensitive**: `src/approval.rs`, `src/config.rs`, `src/commands/claim.rs`,
  `src/commands/download.rs`, `src/sanitize.rs`, `src/provider/fabcli/exec.rs`, `scripts/install-fab.*`,
  `.github/workflows/`.
