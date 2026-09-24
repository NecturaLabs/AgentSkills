# Changelog

## 5.0.0 — 2026-09-24

AgentSkills becomes an installable copy of the NecturaLabs Claude Code and Codex setup.

### Breaking changes

- **`threat-review` is removed**, replaced by Cloudflare's
  [`security-audit`](https://github.com/cloudflare/security-audit-skill). To migrate:
  1. Update the plugin (`claude plugin update necturalabs@necturalabs`; in Codex,
     `codex plugin marketplace upgrade necturalabs`). If you linked skills with
     `scripts/install.sh`, run `bash scripts/uninstall.sh` from the updated checkout: it still
     removes the old `threat-review` links.
  2. Install the replacement: `claude plugin install security-audit@necturalabs` and
     `codex plugin add security-audit@necturalabs`.
  3. Point your routing row at `security-audit:security-audit`, keeping its trigger text (auth,
     sessions, tokens, crypto, secrets, external input, deserialization, file or network
     boundaries, permissions or dependencies — before the review).
- **The standalone `necturalabs-fab` plugin and marketplace are retired.** The Fab skill is now
  `necturalabs:fab`, inside this plugin. To migrate: `claude plugin uninstall
  necturalabs-fab@necturalabs-fab`, `claude plugin marketplace remove necturalabs-fab`,
  `codex plugin remove necturalabs-fab@necturalabs-fab` and
  `codex plugin marketplace remove necturalabs-fab`, or run the old installer's `--uninstall`, which
  [`scripts/install-fab.sh`](scripts/install-fab.sh) `--uninstall` also handles. Rename routing
  rows from `necturalabs-fab:necturalabs-fab` to `necturalabs:fab`.
- **The `necturalabs-fab` CLI follows the AgentSkills version.** Its own 0.2.x line is retired;
  0.2.1 was the last. Binaries are published with AgentSkills releases, and the installers are
  now [`scripts/install-fab.sh`](scripts/install-fab.sh) and
  [`scripts/install-fab.ps1`](scripts/install-fab.ps1). They install only FabCLI and the binary;
  the skill comes with the plugin.

### Added

- The Fab CLI's source, tests, docs and history, merged under `cli/fab/` and `docs/fab/`, with
  its CI and release builds (Linux, Windows, macOS) on GitHub-hosted runners.
- The `necturalabs` marketplace lists every plugin the setup uses that no official or vendor
  marketplace carries, each pinned to an upstream commit and installed straight from upstream:
  `security-audit`, `superpowers`, `web-design-guidelines`, `remotion`, and the optional
  `vercel-composition-patterns`, `vercel-react-view-transitions` and `vercel-react-native-skills`,
  plus connector plugins of our own for the Blender and Godot MCP servers and a TypeScript 7
  language server.
- A README section an agent can follow to offer the whole setup as a checklist, and the
  recommended settings and worker agents under `setup/`.
- `install.sh` and `doctor.sh` recognise the plugin installed in Codex and make no Codex links
  beside it.

### Changed

- `examples/global-agents.md` follows the current working agreement: a skill in use runs as
  written, with listed guards that still apply, and agent tooling installs only from official or
  reputable marketplaces.
