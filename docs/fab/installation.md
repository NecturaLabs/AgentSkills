# Installation

`necturalabs-fab` is the command-line half of the `necturalabs:fab` skill. The skill ships in the
`necturalabs` plugin (see the AgentSkills [README](../../README.md)); this step installs the two
binaries it drives. One command installs them and one command removes them.

**Linux and macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.sh | sh
```

**Windows (PowerShell)**

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.ps1 | iex"
```

The Windows command runs the installer in its own PowerShell process, so nothing it sets leaks into
your session. If an anonymous download fails, the installer retries through a signed-in GitHub CLI
(`gh`) when one is available.

The installer:

1. installs **FabCLI 0.1.0**, the marketplace backend, from its upstream releases
   (`zirklerite/FabCLI`, GPL-3.0; never bundled here) after checking its SHA-256 against a value
   pinned in the script (skipped if a supported FabCLI is already on `PATH`);
2. installs **necturalabs-fab** from the AgentSkills release — a checksum-verified release build, or
   a `cargo` build where no release build exists for the platform;
3. offers to **sign in** (Epic's sign-in page opens in your default browser; you paste the code it
   shows back into the terminal), then runs `necturalabs-fab doctor`.

Install the binary from the same AgentSkills release as the `necturalabs` plugin, so the skill
matches the binary it describes; `necturalabs-fab doctor` warns when they differ. The installer never overwrites a
`fabcli` it did not install: if the bin directory already holds a foreign one, it stops.

Binaries go to `~/.local/bin` (`%USERPROFILE%\.local\bin` on Windows, added to the user `PATH`).
Everything the installer creates is recorded in a manifest under `~/.local/share/necturalabs-fab`
(`%LOCALAPPDATA%\necturalabs-fab` on Windows).

Options (after `sh -s --` on Linux/macOS, as parameters on Windows). Under `irm | iex` parameters
cannot be passed, so each also has an environment variable, read by both installers:

| `install-fab.sh` | `install-fab.ps1` | Environment | Effect |
|---|---|---|---|
| `--bin-dir DIR` | `-BinDir DIR` | `NECTURALABS_FAB_BIN_DIR` | Install binaries elsewhere (absolute path). |
| `--version TAG` | `-Version TAG` | `NECTURALABS_FAB_VERSION` | Install this AgentSkills release, e.g. `v5.0.0`. |
| `--no-login` | `-NoLogin` | `NECTURALABS_FAB_NO_LOGIN=1` | Don't offer to sign in. |
| — | `-NoModifyPath` | `NECTURALABS_FAB_NO_MODIFY_PATH=1` | Don't add the bin directory to the user `PATH`. |
| `-y` | `-Yes` | — | Answer yes to every question. |
| `--source DIR` | `-Source DIR` | — | Build from a checkout (automatic when run from one). |

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.sh | sh -s -- --uninstall
```

```powershell
powershell -ExecutionPolicy ByPass -c "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.ps1))) -Uninstall"
```

Uninstall removes exactly what the manifest records and nothing else:

- the `necturalabs-fab` Claude Code and Codex plugins and marketplace entries that an installer from
  before AgentSkills 5.0.0 added, plus the plugin caches both harnesses otherwise leave behind;
- FabCLI, if the installer installed it: it is signed out first (FabCLI deletes its token, its
  keyring / Credential Manager entry, the sign-in browser data and its library cache), then its
  binary and state directory are removed — unless FabCLI's state directory existed before the
  install, in which case the sign-in is yours and is kept;
- the necturalabs-fab binary, its `PATH` entry on Windows, the bin directory if the installer created
  it and it is now empty, its user config (`--keep-config` / `-KeepConfig` keeps it), its licence
  cache and the manifest.

A FabCLI that was already installed beforehand is left alone. Project `.necturalabs-fab.toml` files and
downloaded assets are yours and are never touched.

If any step fails, uninstall says which, keeps that step's manifest entry and exits non-zero;
running it again retries only what is left.

`scripts/test-fab-installer.sh` performs this round trip in a throwaway `HOME` and fails if any file
named after necturalabs-fab or FabCLI, or any reference to them, is left behind. It also checks that a foreign `fabcli` is never overwritten and that pre-existing FabCLI
state survives uninstall. A throwaway `HOME` does not isolate the OS keyring, so the script cuts
itself off from the D-Bus session bus (and refuses to run on macOS) to keep uninstall's sign-out away
from your real FabCLI key. CI runs it on a GitHub-hosted Linux runner.

## Update

Update the `necturalabs` plugin (see the AgentSkills README), then re-run the install command: it
installs the latest release of necturalabs-fab. FabCLI stays at the pinned version.

## Platform notes

| Platform | necturalabs-fab | FabCLI | Verified |
|---|---|---|---|
| Linux x86-64 | release build (static musl) | release build | locally and in CI |
| Windows x86-64 | release build | release build | tests run in CI on Windows; `install-fab.ps1` round trip not run since the merge |
| macOS arm64 | release build | **no build published** — install FabCLI from source if you need it | tests run in CI on macOS; installer not verified |
| other | built with `cargo` | — | not verified |

FabCLI's sign-in window needs WebKitGTK on Linux: `webkit2gtk-4.1` on Arch,
`libwebkit2gtk-4.1-0 libsoup-3.0-0` on Debian/Ubuntu. The installer warns when they are missing.
The default sign-in uses your browser and needs no WebKitGTK; the account session for claiming and
ownership (`necturalabs-fab auth login --run --account`) still opens FabCLI's own window.

## Sign in later

```bash
necturalabs-fab auth login --run
necturalabs-fab auth status
```

There are two sessions:

- **marketplace reads** — search, inspect, library, download. `auth login --run` opens Epic's
  sign-in page in your default browser; you paste the code it shows. Refreshed automatically for
  about a year.
- **account actions** — claim and ownership. `auth login --run --account` opens FabCLI's sign-in
  window. Lasts about 90 days; `auth status` reports the days left.

## Developing from a checkout

```bash
sh scripts/install-fab.sh            # builds cli/fab from this checkout
sh scripts/install-fab.sh --uninstall
```

Run from an AgentSkills checkout, the installer builds necturalabs-fab from `cli/fab` with `cargo`.
The skill in `skills/fab` reaches both harnesses through AgentSkills' own `scripts/install.sh`.

## FabCLI versions

necturalabs-fab accepts FabCLI `>=0.1.0, <0.2.0`. Outside that range every data command fails with
`FAB_PROVIDER_UNSUPPORTED_VERSION` before contacting anything, because FabCLI's output is only
verified for the versions in range. To try a newer FabCLI before necturalabs-fab supports it, set
`fabcli.version-requirement` in your **user** config (`necturalabs-fab config path`) — at your own risk.
