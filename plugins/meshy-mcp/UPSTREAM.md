# meshy-mcp

A connector plugin: it holds only its manifest and `.mcp.json`, which starts `meshy-mcp-server`
from `PATH`. No Meshy code is redistributed here. Claude Code only: the API key comes from the
plugin's `sensitive` `userConfig` option, which Claude Code prompts for when the plugin is enabled
and keeps in its secure credential store, never in `settings.json` or this directory.

| Piece | Upstream | Revision | License |
|---|---|---|---|
| MCP server `@meshy-ai/meshy-mcp-server` | https://github.com/meshy-dev/meshy-mcp-server | tag `v0.5.2`, commit `10e882abbb8b123f140556678e75f1012ccb69a2` | MIT |

The manifest and this file are NecturaLabs' own, under the repository's MIT license.

## Install the server

Upstream documents only `npx`, which the setup's marketplace-only policy rules out.
`scripts/tools.sh install meshy-mcp-server` (Node.js 22 or newer) clones the repository, checks
out the pinned revision from `setup/tools.tsv`, moves the lockfile's advisories to the in-range
versions an `npx` install would resolve (`npm audit fix`, never `--force`), builds, and links
`meshy-mcp-server` into `~/.local/bin`.

At `v0.5.2` one moderate advisory remains after that, in `qs`, pinned by `express`, which serves
only `TRANSPORT=http`; this connector uses stdio.

## Behavior to know

- `MESHY_API_HOST` is pinned in `.mcp.json`. The server loads a `.env` from the session's working
  directory, and a variable already set is never overridden, so a project's `.env` cannot send the
  key to another host.
- The server checks the key against the Meshy API at startup and exits if it is missing or invalid,
  which shows as a failed MCP connection.
- Downloads go to `meshy_output/` under the session's working directory. Most tools spend Meshy
  credits; `meshy_check_balance` and `meshy_analyze_printability` are free.

## Refresh

`scripts/tools.sh status --remote meshy-mcp-server` lists upstream's newest tags. To move, change
the `rev` in `setup/tools.tsv`, the revision here, the manifest and the marketplace entry; each
machine then runs `scripts/tools.sh update meshy-mcp-server`. Switch to an official or Meshy
marketplace plugin if one ships, and delete this connector.
