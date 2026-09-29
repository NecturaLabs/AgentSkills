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

Upstream documents only `npx`, which the setup's marketplace-only policy rules out, so build the
pinned tag and put its binary on `PATH` (Node.js 22 or newer):

```bash
D=~/.local/share/meshy-mcp-server
git clone --depth 1 --branch v0.5.2 https://github.com/meshy-dev/meshy-mcp-server.git "$D/server-src"
cd "$D/server-src"
npm ci --ignore-scripts
npm audit fix --ignore-scripts   # in-range fixes only, never --force
npm run build && npm audit --omit=dev
mkdir -p ~/.local/bin && ln -s "$D/server-src/dist/index.js" ~/.local/bin/meshy-mcp-server
chmod +x "$D/server-src/dist/index.js"
```

At `v0.5.2` the lockfile pins packages with known advisories; `npm audit fix` moves them to the
in-range versions an `npx` install would resolve. One moderate advisory remains in `qs`, pinned by
`express`, which serves only `TRANSPORT=http`; this connector uses stdio.

## Behavior to know

- `MESHY_API_HOST` is pinned in `.mcp.json`. The server loads a `.env` from the session's working
  directory, and a variable already set is never overridden, so a project's `.env` cannot send the
  key to another host.
- The server checks the key against the Meshy API at startup and exits if it is missing or invalid,
  which shows as a failed MCP connection.
- Downloads go to `meshy_output/` under the session's working directory. Most tools spend Meshy
  credits; `meshy_check_balance` and `meshy_analyze_printability` are free.

## Refresh

Rebuild at the new tag (restore `package-lock.json` first), rerun the audit steps, and update the
revision here, in the manifest and in the marketplace entry. Switch to an official or Meshy
marketplace plugin if one ships, and delete this connector.
