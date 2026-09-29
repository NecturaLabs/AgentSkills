# blender-lab-mcp

A connector plugin: it holds only its manifests and `.mcp.json`, which starts `blender-mcp` from
`PATH`. No Blender Lab code is redistributed here.

| Piece | Upstream | Revision | License |
|---|---|---|---|
| MCP server `blender-mcp` (the `mcp/` package) | https://projects.blender.org/lab/blender_mcp | commit `ff54e4d8f6b09502f2f466189cca0e52b4a91643` (2026-09-11) | GPL-3.0-or-later |
| Blender add-on (the `addon/` directory) | same repository and revision | | GPL-3.0-or-later |

The manifests and this file are NecturaLabs' own, under the repository's MIT license.

## Install the server

Blender Foundation publishes no package. `scripts/tools.sh install blender-mcp` clones the
repository, checks out the pinned revision from `setup/tools.tsv`, installs its `mcp/` package in
a virtual environment beside it, and links `blender-mcp` into `~/.local/bin`.

Then install the add-on from the same revision into Blender (Edit → Preferences → Add-ons →
Install from Disk, pointing at a zip of the build's `addon/` directory, under
`<tools dir>/blender-mcp/builds/`) and enable it. The server talks to that add-on.

## Refresh

`scripts/tools.sh status --remote blender-mcp` lists upstream's newest tags. To move, change the
`rev` in `setup/tools.tsv`, the revision here, both manifests' descriptions and the marketplace
entry; each machine then runs `scripts/tools.sh update blender-mcp` and reinstalls the add-on from
the new build.
