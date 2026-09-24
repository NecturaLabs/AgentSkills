# blender-lab-mcp

A connector plugin: it holds only its manifests and `.mcp.json`, which starts `blender-mcp` from
`PATH`. No Blender Lab code is redistributed here.

| Piece | Upstream | Revision | License |
|---|---|---|---|
| MCP server `blender-mcp` (the `mcp/` package) | https://projects.blender.org/lab/blender_mcp | commit `ff54e4d8f6b09502f2f466189cca0e52b4a91643` (2026-09-11) | GPL-3.0-or-later |
| Blender add-on (the `addon/` directory) | same repository and revision | | GPL-3.0-or-later |

The manifests and this file are NecturaLabs' own, under the repository's MIT license.

## Install the server

Blender Foundation publishes no package, so install the pinned revision from its own repository
with a per-user Python tool manager:

```bash
uv tool install "git+https://projects.blender.org/lab/blender_mcp.git@ff54e4d8f6b09502f2f466189cca0e52b4a91643#subdirectory=mcp"
blender-mcp --help
```

Then install the add-on from the same revision into Blender (Edit → Preferences → Add-ons →
Install from Disk, pointing at a zip of `addon/`) and enable it. The server talks to that add-on.

## Refresh

Pick a new upstream commit, reinstall with it, and update the revision here, in both manifests'
descriptions, and in the marketplace entry.
