# godot-mcp-toolkit

A connector plugin: it holds its manifests, `.mcp.json`, which starts `godot-mcp-server` from
`PATH`, and two patches of our own to the bridge (`patches/`). No other NPGameDev code is
redistributed here.

| Piece | Upstream | Revision | License |
|---|---|---|---|
| Bridge `@npgamedev/godot-mcp-server` | https://github.com/NPGameDev/godot-mcp-server | tag `v1.0.2`, commit `2034c32b2a69ad259141060502b4f696e13a7cb9`, plus `patches/` | MIT |
| Editor add-on `godot_mcp_toolkit` | https://github.com/NPGameDev/godot-mcp-toolkit | release `v1.0.2`, commit `7e801d7b6603eb908dfb7e58bd497daa74a6502b` | MIT |

The manifests, the patches and this file are NecturaLabs' own; the manifests and this file are
under the repository's MIT license. The patches modify the bridge and carry lines of its source, so
they are under the bridge's MIT license, Copyright (c) 2026 NPGameDev, whose full text travels
with them in `patches/LICENSE`.

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

`scripts/tools.sh install godot-mcp-server` (Node.js 22 or newer) clones the bridge, checks out
the pinned revision from `setup/tools.tsv`, applies `patches/` in order, runs upstream's unit
tests, builds, and links `godot-mcp-server` into `~/.local/bin`. `scripts/tools.sh status` shows
whether the build matches the pin.

Each Godot project carries the matching `godot_mcp_toolkit` add-on (release `v1.0.2` zip) in
`addons/`, enabled in Project Settings → Plugins.

## Refresh

`scripts/tools.sh status --remote godot-mcp-server` lists upstream's newest tags. To move to one,
change its `rev` in `setup/tools.tsv`, keep the patches that still apply, bump the revision here,
in both manifests and in the marketplace entry, and update every project's add-on to the same
release; each machine then runs `scripts/tools.sh update godot-mcp-server`.
