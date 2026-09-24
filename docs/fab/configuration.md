# Configuration reference

Precedence, highest first: command-line flags → `NECTURALABS_FAB_*` environment variables → the
nearest project config (`.necturalabs-fab.toml`, `necturalabs-fab.toml` or `.necturalabs/fab.toml`, searched
from the working directory upwards) → the user config → built-in defaults. Each layer overrides
individual keys, not whole sections. Unknown keys are an error (`FAB_CONFIG_INVALID`), so a typo
never silently falls back to a default.

The project config is untrusted (it comes with the repository), so it may not set `provider`,
`fabcli.path`, `fabcli.version-requirement`, `approval.claim`, `approval.download` or
`download.overwrite`, and its `download.directory` must be a relative path inside the project.
Those rows are marked **user** below: set them in the user config, an env var or a flag.

User config location: `~/.config/necturalabs-fab/config.toml` (Linux), `~/Library/Application
Support/necturalabs-fab/config.toml` (macOS), `%APPDATA%\necturalabs-fab\config.toml` (Windows).
An absolute `XDG_CONFIG_HOME` relocates it on every platform. `NECTURALABS_FAB_CONFIG` or
`--config` replaces it. `necturalabs-fab config show --json` prints the
effective values and which layers applied; `config init` writes a commented template.

| Key | Env var | Flag | Default | Meaning |
|---|---|---|---|---|
| `provider` **user** | `NECTURALABS_FAB_PROVIDER` | `--provider` | `fabcli` | Active provider. |
| `fabcli.path` **user** | `NECTURALABS_FAB_FABCLI_PATH` | `--fabcli-path` | `fabcli` | Provider executable. |
| `fabcli.timeout-seconds` | `NECTURALABS_FAB_TIMEOUT_SECONDS` | `--timeout` | `120` | Per-call deadline. Library enumeration uses at least 300. |
| `fabcli.download-timeout-seconds` | `NECTURALABS_FAB_DOWNLOAD_TIMEOUT_SECONDS` | — | `7200` | Download deadline. |
| `fabcli.version-requirement` **user** | `NECTURALABS_FAB_VERSION_REQUIREMENT` | — | `>=0.1.0, <0.2.0` | Accepted FabCLI versions (semver range). |
| `fabcli.library-cache` | `NECTURALABS_FAB_LIBRARY_CACHE` | — | `true` | Let FabCLI cache the library (24 h). |
| `download.directory` | `NECTURALABS_FAB_DOWNLOAD_DIR` | — | `.` | Root for downloads without `--out`; each listing gets `<root>/<id>`. |
| `download.overwrite` **user** | `NECTURALABS_FAB_OVERWRITE` | `--overwrite` | `refuse` | `refuse`, `force`, `require-empty`. |
| `download.jobs` | — | `--jobs` | FabCLI's (8) | Parallel chunk downloads. |
| `defaults.engine` | `NECTURALABS_FAB_ENGINE` | `--engine` | none | `unreal`, `unity`, `godot`, `blender`, `uefn`, `metahuman`. |
| `defaults.engine-version` | `NECTURALABS_FAB_ENGINE_VERSION` | `--engine-version` | none | e.g. `5.4`. |
| `defaults.prefer-owned` | `NECTURALABS_FAB_PREFER_OWNED` | `--[no-]prefer-owned` | `true` | Ranking preference. |
| `defaults.prefer-free` | `NECTURALABS_FAB_PREFER_FREE` | `--[no-]prefer-free` | `true` | Ranking preference. |
| `defaults.count` | `NECTURALABS_FAB_COUNT` | `--count` | `24` | Results per search, 1–500. |
| `defaults.hydrate` | — | `--hydrate` | `6` | Candidates `find` enriches with listing detail. |
| `approval.claim` **user** | `NECTURALABS_FAB_APPROVAL_CLAIM` | `--approve` (per call) | `require` | `require`, `allow`, `deny`. |
| `approval.download` **user** | — | — | `allow` | `allow` or `deny`, for local writes. |
| `output.mode` | `NECTURALABS_FAB_OUTPUT` | `--json`, `--human`, `--output` | `auto` | `auto` = JSON when stdout is not a terminal. |

Boolean env values accept `1/0`, `true/false`, `yes/no`, `on/off`. There is no setting that
enables purchasing.

`CLAUDE_CONFIG_DIR` and `CODEX_HOME` are honoured by `skill status` and `doctor` when locating
the harnesses' plugin state.
