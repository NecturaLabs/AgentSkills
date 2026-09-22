# Installation

One command installs everything and one command removes it.

**Linux and macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/NecturaLabs/FabCLI/main/scripts/install.sh | sh
```

**Windows (PowerShell)**

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/NecturaLabs/FabCLI/main/scripts/install.ps1 | iex"
```

The Windows command runs the installer in its own PowerShell process, so nothing it sets leaks into
your session.

**While the repository is private**, anonymous downloads return 404. Members of the NecturaLabs
organisation install through the GitHub CLI instead (`gh auth login` first); the installer then
also fetches the release through `gh`, and Claude Code and Codex clone the marketplace with your
git credentials:

```bash
gh api -H 'Accept: application/vnd.github.raw' repos/NecturaLabs/FabCLI/contents/scripts/install.sh | sh
gh api -H 'Accept: application/vnd.github.raw' repos/NecturaLabs/FabCLI/contents/scripts/install.sh | sh -s -- --uninstall
```

```powershell
powershell -ExecutionPolicy ByPass -c "gh api -H 'Accept: application/vnd.github.raw' repos/NecturaLabs/FabCLI/contents/scripts/install.ps1 | Out-String | iex"
```

The installer:

1. installs **FabCLI 0.1.0**, the marketplace backend, after checking its SHA-256 against a value
   pinned in the script (skipped if a supported FabCLI is already on `PATH`);
2. installs **necturalabs-fab** — a checksum-verified release build, or a `cargo` build where no release
   build exists for the platform;
3. installs the **agent skill as a plugin** through each harness's own marketplace, for every
   harness it finds: `claude plugin marketplace add` + `claude plugin install` for Claude Code,
   `codex plugin marketplace add` + `codex plugin add` for Codex;
4. offers to **sign in** (Epic's sign-in page opens in your default browser; you paste the code it
   shows back into the terminal), then runs `necturalabs-fab doctor`.

The binary and both plugin marketplaces come from **one release tag** — the latest release unless
you pick one — so the skill always matches the binary it describes. The installer never overwrites a
`fabcli` it did not install: if the bin directory already holds a foreign one, it stops.

Binaries go to `~/.local/bin` (`%USERPROFILE%\.local\bin` on Windows, added to the user `PATH`).
Everything the installer creates is recorded in a manifest under `~/.local/share/necturalabs-fab`
(`%LOCALAPPDATA%\necturalabs-fab` on Windows).

Options (after `sh -s --` on Linux/macOS, as parameters on Windows). Under `irm | iex` parameters
cannot be passed, so each also has an environment variable, read by both installers:

| `install.sh` | `install.ps1` | Environment | Effect |
|---|---|---|---|
| `--bin-dir DIR` | `-BinDir DIR` | `NECTURALABS_FAB_BIN_DIR` | Install binaries elsewhere (absolute path). |
| `--version TAG` | `-Version TAG` | `NECTURALABS_FAB_VERSION` | Install this release, e.g. `v0.1.0`. |
| `--no-plugin` | `-NoPlugin` | `NECTURALABS_FAB_NO_PLUGIN=1` | Skip the Claude Code / Codex plugin. |
| `--no-login` | `-NoLogin` | `NECTURALABS_FAB_NO_LOGIN=1` | Don't offer to sign in. |
| — | `-NoModifyPath` | `NECTURALABS_FAB_NO_MODIFY_PATH=1` | Don't add the bin directory to the user `PATH`. |
| `-y` | `-Yes` | — | Answer yes to every question. |
| `--source DIR` | `-Source DIR` | — | Build from a checkout (automatic when run from one). |

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/NecturaLabs/FabCLI/main/scripts/install.sh | sh -s -- --uninstall
```

```powershell
powershell -ExecutionPolicy ByPass -c "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NecturaLabs/FabCLI/main/scripts/install.ps1))) -Uninstall"
```

Uninstall removes exactly what the manifest records and nothing else:

- the Claude Code and Codex plugins and marketplace entries it added, plus the plugin caches both
  harnesses otherwise leave behind;
- FabCLI, if the installer installed it: it is signed out first (FabCLI deletes its token, its
  keyring / Credential Manager entry, the sign-in browser data and its library cache), then its
  binary and state directory are removed — unless FabCLI's state directory existed before the
  install, in which case the sign-in is yours and is kept;
- the necturalabs-fab binary, its `PATH` entry on Windows, the bin directory if the installer created
  it and it is now empty, its user config (`--keep-config` / `-KeepConfig` keeps it) and the
  manifest.

A FabCLI that was already installed beforehand is left alone. Project `.necturalabs-fab.toml` files and
downloaded assets are yours and are never touched.

If any step fails, uninstall says which, keeps that step's manifest entry and exits non-zero;
running it again retries only what is left.

`scripts/test-installer.sh` performs this round trip in a throwaway `HOME` and fails if any file
named after necturalabs-fab or FabCLI, or any reference to them in Claude Code or Codex state, is left
behind. It also checks that a foreign `fabcli` is never overwritten and that pre-existing FabCLI
state survives uninstall. A throwaway `HOME` does not isolate the OS keyring, so the script cuts
itself off from the D-Bus session bus (and refuses to run on macOS) to keep uninstall's sign-out away
from your real FabCLI key. CI runs it on Linux and an equivalent check on Windows.

## Update

Re-run the install command. It installs the latest release of necturalabs-fab, moves both plugin
marketplaces it added to that same release, and updates the plugins (`claude plugin update`,
`codex plugin add`). FabCLI stays at the pinned version.

## Platform notes

| Platform | necturalabs-fab | FabCLI | Verified |
|---|---|---|---|
| Linux x86-64 | release build (static musl) | release build | locally and in CI |
| Windows x86-64 | release build | release build | CI installer round trip |
| macOS | built with `cargo` | **no build published** — install FabCLI from source if you need it | not verified |

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
sh scripts/install.sh            # builds this checkout and installs its plugin
sh scripts/install.sh --uninstall
```

Run from a checkout, the installer builds necturalabs-fab with `cargo` and registers the checkout
itself as the plugin marketplace, so edits to `plugin/` reach both harnesses after a re-run.

## FabCLI versions

necturalabs-fab accepts FabCLI `>=0.1.0, <0.2.0`. Outside that range every data command fails with
`FAB_PROVIDER_UNSUPPORTED_VERSION` before contacting anything, because FabCLI's output is only
verified for the versions in range. To try a newer FabCLI before necturalabs-fab supports it, set
`fabcli.version-requirement` in your **user** config (`necturalabs-fab config path`) — at your own risk.
