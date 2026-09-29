# godot-mcp-toolkit

A connector plugin: it holds its manifests, `.mcp.json`, which starts `godot-mcp-server` from
`PATH`, and two patches of our own to the bridge (`patches/`). No other NPGameDev code is
redistributed here.

| Piece | Upstream | Revision | License |
|---|---|---|---|
| Bridge `@npgamedev/godot-mcp-server` | https://github.com/NPGameDev/godot-mcp-server | tag `v1.0.2`, commit `2034c32b2a69ad259141060502b4f696e13a7cb9`, plus `patches/` | MIT |
| Editor add-on `godot_mcp_toolkit` | https://github.com/NPGameDev/godot-mcp-toolkit | release `v1.0.2`, commit `7e801d7b6603eb908dfb7e58bd497daa74a6502b` | MIT |

The manifests, the patches and this file are NecturaLabs' own; the manifests and this file are
under the repository's MIT license, and the patches under the bridge's MIT license.

## Patches

Upstream `v1.0.2` has two faults these fix, each with regression tests:

- `0001` — a game run with no editor open registers a stand-in entry with `"port": -1`; unpatched,
  the bridge took it as the editor's port, crashing at startup (`ws://127.0.0.1:-1`) or failing
  every later call after re-discovery. The bridge now ignores entries without a valid editor port
  and re-reads the registry after a failed connection or auth.
- `0002` — the channel re-discovery swaps in never sent the server's response-size limits to the
  editor; both channel sites now share one factory that does.

Drop a patch once an upstream release fixes its fault: build that tag without it and check that
its tests' scenarios still pass.

## Install the bridge

Build it from the pinned tag so the version cannot drift between sessions, and put its binary on
`PATH` (Node.js 22 or newer):

```bash
D=~/.local/share/godot-mcp-toolkit
git clone --depth 1 --branch v1.0.2 https://github.com/NPGameDev/godot-mcp-server.git "$D/server-src"
cd "$D/server-src"
git -c user.name=local -c user.email=local@localhost am --committer-date-is-author-date \
  ~/.claude/plugins/marketplaces/necturalabs/plugins/godot-mcp-toolkit/patches/*.patch
npm ci --ignore-scripts && npm run test:unit && npm run build && npm prune --omit=dev --ignore-scripts
npm audit --omit=dev
mkdir -p ~/.local/bin && ln -s "$D/server-src/dist/index.js" ~/.local/bin/godot-mcp-server
chmod +x "$D/server-src/dist/index.js"
```

Each Godot project carries the matching `godot_mcp_toolkit` add-on (release `v1.0.2` zip) in
`addons/`, enabled in Project Settings → Plugins.

## Refresh

Rebuild at the new tag with the patches that still apply, update every project's add-on to the
same release, and bump the revision here, in both manifests and in the marketplace entry.
