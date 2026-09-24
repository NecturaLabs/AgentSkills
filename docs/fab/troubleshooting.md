# Troubleshooting

Start with `necturalabs-fab doctor`. Each failing check carries a hint; the table below covers the
rest. Exit codes and error codes: `skills/fab/references/errors.md`.

| Symptom | Cause | Fix |
|---|---|---|
| `FAB_PROVIDER_NOT_INSTALLED` | `fabcli` not on `PATH`. | Install it (`docs/fab/installation.md`) or set `fabcli.path`. |
| `FAB_PROVIDER_UNSUPPORTED_VERSION` | FabCLI outside `>=0.1.0, <0.2.0`. | `fabcli update --to 0.1.0`, or update necturalabs-fab. |
| `FAB_PROVIDER_PROTOCOL` on commands that used to work | Epic/Fab changed an undocumented endpoint, or FabCLI's output changed. | Run the failing `fabcli` command by hand; check FabCLI releases for a fix; report it. Retrying will not help. |
| `FAB_AUTH_REQUIRED` | No session. | `necturalabs-fab auth login --run` (browser; paste the code it shows). |
| `FAB_AUTH_EXPIRED`, or `claim`/`ownership` fail while `search` works | The ~90-day account session lapsed or was never created; the read session is separate. | `necturalabs-fab auth login --run --account`. |
| Account sign-in window never appears (Linux) | WebKitGTK missing, or no graphical session. | Install the libraries in `docs/fab/installation.md`. Reads sign in through the browser and do not need it. |
| `no encryption key in OS keystore` from FabCLI | FabCLI's key was removed from the keyring (a sign-out, a keyring reset, or another user account). | Sign in again: `necturalabs-fab auth login --run`. |
| `promos` lists nothing while fab.com shows free listings | Fab changed how discounts are reported, or the listing detail could not be fetched (see `warnings`). | Run `fabcli search --filter=min_discount_percentage=100` by hand and report what it returns. |
| `FAB_TIMEOUT` on `library`, `download` or `--owned-only` | The first library fetch walks the whole library (~100 s for 1,000 items). | Raise `--timeout`; leave `fabcli.library-cache` on so later calls take milliseconds. |
| `FAB_RATE_LIMITED` | Too many calls, often parallel ones. | Wait 30 s; run marketplace commands one at a time. |
| `search` returns nothing with `--filter` | Fab ignores unknown filter keys and returns zero results instead of an error. | Use the modelled flags (`--style`, `--feature`, …) or check the key's spelling. |
| `--engine-version` filters nothing | Search results carry no version data. | Add `--hydrate N`, or use `find`, which enriches the top candidates. |
| `FAB_AMBIGUOUS_VARIANT` on download | The listing ships several engine versions or platforms. | Re-run with `--engine-version` (and `--platform`) from `error.details.available`. |
| `FAB_OUTPUT_CONFLICT` | The directory already holds a download (a `necturalabs-fab.asset.json`) or colliding files. | New `--out`, or `--overwrite force` if replacing is intended. |
| `FAB_CONFIG_INVALID` | Unknown key or bad value in a config file or env var, or a project `.necturalabs-fab.toml` setting a key only your user config may set. | The message names the file and key; `necturalabs-fab config show` shows every layer. |
| Skill not picked up by Claude Code or Codex | Plugin not installed, or a hand-placed copy in `~/.claude/skills`, `~/.agents/skills` or `~/.codex/skills` competing with it. | `necturalabs-fab skill status`; remove any hand-placed copy it reports; re-run the installer. Restart the harness after installing. |

To see exactly what FabCLI returned, add `--raw` (payloads on each asset) or run the equivalent
`fabcli` command yourself; FabCLI prints JSON on stdout and `{"error":{…}}` on stderr.
