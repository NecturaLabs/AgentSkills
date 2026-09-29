# Changelog

## Unreleased

### Changed

- The recommended settings save Sonnet 5.5 at low effort, as the machine they back up does.
- `examples/global-agents.md` names the repository that backs up the setup and keeps the local
  setup as the source of truth: changes mirror to the repository, never the other way.

## 5.1.0 — 2026-09-29

### Changed

- Compactions are made safe to hit at any moment. The recommended settings compact at 500k
  tokens (`autoCompactWindow`), run the new `compact-resume.py` SessionStart hook after each
  compaction (it prints the session's `checklist.md`, the other scratchpad files and
  `git status`) and show context used against that window in the new `statusline.py` status
  line. `examples/global-agents.md` keeps a checklist for any task of more than a few steps,
  written ahead of the work, treats it and the disk as the record after a compaction, and tells
  the compaction summary what to keep. Copy both scripts in as the README's setup section says.
- `statusline.py` becomes `context-meter.py`, which also runs as a UserPromptSubmit and
  PostToolUse hook: every prompt carries one line with the context used against the auto-compact
  window, and a tool call adds it only when 60%, 80%, 90% or 95% is first reached, so the model
  sees a compaction coming. `examples/global-agents.md` brings the checklist up to date from 80%
  and reaches a clean point from 90%. `compact-resume.py` takes the hook input's `scratchpad_dir`
  when present and leaves hidden scratchpad files out of its list. Replace
  `~/.claude/statusline.py` with `~/.claude/hooks/context-meter.py` and point `statusLine` at it.
- The worker agents in `setup/claude/agents/` pin a model as well as an effort: `opus-low` to
  `opus-xhigh` for judgment-led, long-horizon or costly-to-fail work, and `sonnet-low` to
  `sonnet-xhigh` as the default for work with a clear spec and a way to check it. They replace
  `worker-low` to `worker-xhigh`: delete those from `~/.claude/agents/`, copy the new files in, and
  dispatch by the new names.
- `agent-orchestration` defines the strong tier as the strongest the setup provides (the `opus-*`
  types in this setup) rather than the harness's most capable model, which a setup may exclude, and
  its tier table gains the long-horizon and quick-expert-look rows.
- `examples/global-agents.md` is brought up to date: compaction-readiness rules, other skills load
  only when their description fits, Codex limited to generating assets, a scratch-directory rule,
  the delegation routing (`sonnet-*` by default, `opus-*` for strong rows, latest aliases, never
  Fable) and one review per checkpoint.
- The recommended Claude Code settings use model `opus` rather than `opus[1m]`.
- The `remotion` entry pins remotion-dev/skills 4.0.529 (`cf49eff`), its latest.
- The recommended settings drop the saved effort for Opus 5 and Sonnet 5, which the `opus` and
  `sonnet` aliases no longer reach; Opus 5.5 stays at `high`. They turn on auto-scroll and enable
  the Scenario, Sentry and Meshy plugins below.
- `examples/global-agents.md` dispatches a project's own specialist agent (its `.claude/agents/`)
  before a tier type when one fits, routes custom 2D game art, textures, skyboxes and sprite
  animation to Scenario, and notes the `omarchy` route in the desktop marker. The README's setup
  section describes per-project specialists and per-project plugin opt-outs with
  `skillListingBudgetFraction`.
- `godot-mcp-toolkit` is `1.0.2+fork.2`: its bridge is built with two fixes of our own in
  `plugins/godot-mcp-toolkit/patches/` (a game run's port -1 stand-in is never dialled as the
  editor; a re-discovered channel sends the response limits). Rebuild the bridge as its
  `UPSTREAM.md` now describes.

### Added

- `memory-hygiene`, a skill that keeps saved memories and session handoff notes true: it checks
  each against the repository, merges duplicates, retires finished handoffs, fixes the memory index
  and routes drifted docs to `project-docs`, with its five eval cases.
- `setup/claude/scripts/memory-check.py`, a SessionStart hook that flags memories no longer matching
  the disk (index lines with no file, unlisted files, broken links, named paths that are gone) and
  stays silent otherwise; `tests/memory-check-guard.sh` checks it. Copy it to `~/.claude/hooks/`;
  the recommended `settings.json` registers it.
- The working agreement keeps saved memories current with the change that made them stale, gives
  every checkpoint one hygiene pass, and routes stale memories to `memory-hygiene`. Astra runs only
  on the owner's explicit confirmation, always at high effort.
- `scripts/tools.sh` builds the MCP servers no marketplace or vendor installer ships (Godot,
  Meshy, Blender Lab) from full clones at the revisions pinned in `setup/tools.tsv`, applies our
  patches, links each into `~/.local/bin`, and on `update` swaps to a new build while keeping the
  previous one for servers still running; `status --remote` lists upstream's newest tags. The
  plugins' `UPSTREAM.md` install steps now use it, and `tests/tools-guard.sh` checks it offline.
- `meshy-mcp`, a Claude Code connector for Meshy's official MCP server 0.5.2, built from the pinned
  tag (`plugins/meshy-mcp/UPSTREAM.md`); the API key is a sensitive plugin option kept in Claude
  Code's credential store.
- Setup checklist rows for the Scenario skills (`scenario-skills` marketplace), Sentry and its CLI,
  Higgsfield, and the `meshy-mcp-server` and `sentry` tools; the Codex settings add the Scenario and
  Higgsfield MCP servers.
- `setup/claude/scripts/agent-model-guard.py`, a PreToolUse hook on Agent that names each subagent
  after the model and effort it actually runs on, rewrites a `model` argument that contradicts a
  `<model>-<effort>` type, and refuses a spawn on Fable. Copy it to `~/.claude/hooks/` and make it
  executable; the recommended `settings.json` registers it.

## 5.0.1 — 2026-09-24

### Changed

- superpowers installs from Anthropic's official marketplace, which now pins its latest release
  (6.4.1), so the `necturalabs` marketplace no longer lists it. If you installed
  `superpowers@necturalabs` from 5.0.0: `claude plugin uninstall superpowers@necturalabs`, then
  `claude plugin install superpowers@claude-plugins-official`; in Codex,
  `codex plugin remove superpowers@necturalabs`, then
  `codex plugin add superpowers@claude-plugins-official`.

### Fixed

- `necturalabs-fab doctor` points a missing or mismatched skill at the `necturalabs` plugin rather
  than the retired standalone installer.

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
