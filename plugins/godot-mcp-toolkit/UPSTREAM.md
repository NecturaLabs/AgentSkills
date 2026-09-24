# godot-mcp-toolkit

A connector plugin: it holds only its manifests and `.mcp.json`, which starts `godot-mcp-server`
from `PATH`. No NPGameDev code is redistributed here.

| Piece | Upstream | Revision | License |
|---|---|---|---|
| Bridge `@npgamedev/godot-mcp-server` | https://github.com/NPGameDev/godot-mcp-server | tag `v1.0.2`, commit `2034c32b2a69ad259141060502b4f696e13a7cb9` | MIT |
| Editor add-on `godot_mcp_toolkit` | https://github.com/NPGameDev/godot-mcp-toolkit | release `v1.0.2`, commit `7e801d7b6603eb908dfb7e58bd497daa74a6502b` | MIT |

The manifests and this file are NecturaLabs' own, under the repository's MIT license.

## Install the bridge

Build it from the pinned tag so the version cannot drift between sessions, and put its binary on
`PATH` (Node.js 22 or newer):

```bash
D=~/.local/share/godot-mcp-toolkit
git clone --depth 1 --branch v1.0.2 https://github.com/NPGameDev/godot-mcp-server.git "$D/server-src"
cd "$D/server-src"
npm ci --ignore-scripts && npm run build && npm prune --omit=dev --ignore-scripts
npm audit --omit=dev
mkdir -p ~/.local/bin && ln -s "$D/server-src/dist/index.js" ~/.local/bin/godot-mcp-server
chmod +x "$D/server-src/dist/index.js"
```

Each Godot project carries the matching `godot_mcp_toolkit` add-on (release `v1.0.2` zip) in
`addons/`, enabled in Project Settings → Plugins.

## Refresh

Rebuild at the new tag, update every project's add-on to the same release, and bump the revision
here, in both manifests and in the marketplace entry.
