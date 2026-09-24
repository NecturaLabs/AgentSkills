# necturalabs-fab

Agent-oriented access to the [Fab](https://www.fab.com) marketplace. Coding agents — Claude Code,
Codex, anything that can run a command — use it to find, compare, inspect, claim and download
game-development assets through a stable JSON interface, with purchases impossible and account
changes gated on human approval.

```console
$ necturalabs-fab find "dark gothic ruined castle environment" --engine unreal --json
{"ok":true,"command":"find","requiresApproval":false,"data":{"candidates":[{"rank":1,"score":0.81,
 "signals":{…},"reasons":["already in your library","ships for unreal", …],"asset":{…}}], …}}
```

## Why a wrapper

Fab has no public API. [FabCLI](https://github.com/zirklerite/FabCLI) drives Epic's and Fab's
**undocumented, unversioned** endpoints, which can change without notice. necturalabs-fab puts a
stable contract in front of it: a normalized asset model, fixed error codes and exit codes,
deterministic ranking, an approval model, and a provider trait so FabCLI can be replaced without
touching agents. When upstream moves, you get `FAB_PROVIDER_PROTOCOL`, not wrong answers.

## Install

The `necturalabs:fab` skill ships in the `necturalabs` plugin; install it as the AgentSkills
[README](../../README.md) describes. Then install the CLI and FabCLI:

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.sh | sh
```

```powershell
# Windows
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.ps1 | iex"
```

This installs FabCLI from its upstream releases and necturalabs-fab from AgentSkills releases, and
offers to sign you in. Uninstalling is one command too, and removes everything it added:
[`installation.md`](installation.md).

## Commands

| | |
|---|---|
| `search`, `find`, `recommend` | Marketplace retrieval, ranked discovery, single recommendation |
| `inspect`, `ownership`, `library` | Listing detail, ownership and licences, owned assets |
| `download` | Owned asset to a directory (local write) |
| `claim` | Add a free asset to the library (account mutation — needs `--approve`) |
| `promos` | Fab's current limited-time free listings; `promos claim` claims the unowned ones (needs `--approve`) |
| `auth`, `doctor`, `capabilities`, `config`, `skill` | Operations |

There is no purchase command, flag or setting.

## Documentation

- [`usage.md`](usage.md) — examples for humans and scripts
- [`skills/fab/`](../../skills/fab/SKILL.md) — the agent skill; its
  `references/` hold the command reference and error table
- [`configuration.md`](configuration.md) — every key, env var and flag
- [`security.md`](security.md) — approval model, credentials, untrusted input
- [`architecture.md`](architecture.md) — components and boundaries; ADRs in [`adr/`](adr)
- [`providers.md`](providers.md) — implementing a replacement provider
- [`troubleshooting.md`](troubleshooting.md)
- [`licensing.md`](licensing.md) — MIT here, GPL-3.0 FabCLI kept at arm's length

## Development

The crate lives in [`cli/fab/`](../../cli/fab). From there:

```bash
cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
sh ../../scripts/test-fab-installer.sh   # install/uninstall round trip in a throwaway HOME (downloads FabCLI)
```

The suite needs no network and no Fab account: CLI tests run the real binary against
`mock-fabcli`, a fixture-driven stand-in built from `src/bin/mock-fabcli.rs`. The optional live
check against a real, signed-in FabCLI is read-only:

```bash
cargo test --test live -- --ignored --nocapture
```

## Disclaimer

Not affiliated with Epic Games or Fab. Automated use of undocumented endpoints may breach their
terms of service and put the account at risk; keep usage modest.

MIT licensed, as the rest of AgentSkills. The version follows the AgentSkills version; the
standalone 0.2.x line is retired.
