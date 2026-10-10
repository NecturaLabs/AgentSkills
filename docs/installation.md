# Installation

Verified against Claude Code 2.1.278 (skill precedence and bundled names re-checked on 2.1.280)
and Codex CLI 0.155.1 on Linux; skill naming and the optional dual-harness layout re-checked on Claude Code
2.1.281 and Codex CLI 0.156.1. Where a claim below was not confirmed by running it, that is stated.

The current recommended setup installs external tooling in Claude Code. Codex keeps its built-in
capabilities and is used only for assets and as an additional reviewer. The development installer
and optional dual-harness layouts remain supported; their behavior below is unchanged.

## Current setup snapshot

The public templates mirror the active local setup as of 2026-10-07. Local configuration is the
source of truth; the repository receives generalized copies, never credentials, account state,
project trust entries, personal paths or app-managed internal servers.

- `setup/claude/settings.json` mirrors the portable settings. Opus 5.5, Sonnet 5.5 and Haiku 5.5 use `high` effort, with `sonnet` as the default model.
  Lua, TypeScript and Rust language-server plugins are disabled globally,
  and a project may enable the one it uses.
- Machine-specific storage paths are omitted from the merge-ready template. To use separate
  persistent storage, add `env.CLAUDE_CODE_TMPDIR` for scratch files and
  `env.AGENTSKILLS_TOOLS_DIR` for MCP builds, with your chosen absolute paths before merging. Environment values are literal strings: `$HOME` and `~` are not path
  expansion instructions there. Put scratch files, tools, environments and model weights on the
  chosen persistent storage volume. Hook commands still use `$HOME` because those run in a shell.
- The Scenario group is now `04.-game-art-and-3d`.
  `worker-protocol@worker-protocol` comes from `NecturaLabs/worker-protocol` and applies only to
  explicitly chosen scripted workflows, not plain subagents.
- `cc-plugin-you-should-know@builtin` is a built-in registration, not a marketplace install.
  The local registry retains `netlify@anthropic-plugin-directory`; the current fresh install name
  is `netlify-skills@claude-plugins-official`, as listed in
  the installed official marketplace manifest. The template uses those fresh install names. On an
  existing machine that keeps the legacy registrations, use the corresponding legacy keys instead
  of adding the fresh keys; do not enable a second copy of the same plugin.
- `setup/codex/config.toml` records `gpt-6.1-sol` at `xhigh`, as the working agreement requires.
  Explicit job calls use `codex exec -m gpt-6.1-sol -c model_reasoning_effort=xhigh`. Built-in app plugins and internal
  MCP wiring remain app-managed and are deliberately absent from the template.
- The duplicate-skill hook recognizes marketplaces represented only by installed plugin
  registrations, avoiding false leftover warnings for built-in directories.

Adopt the policy independently of skill installation: resolve every `customize:` marker in
`examples/global-agents.md`, back up any existing policy and adapters, copy the result to
`~/.agents/AGENTS.md`, write only `@~/.agents/AGENTS.md` into `~/.claude/CLAUDE.md`, and link
`$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) to the canonical file. The policy copy stays
local and maintained by its owner. `install.sh --global-agents` also links skills into detected
harnesses, so it is for the optional development layout below, not this setup.

Installation and removal commands below describe procedures, not checks to run during a setup
sync. The offline suite verifies repository-owned installer and hook behavior in disposable
fixtures; it does not authenticate external MCP servers or run the paid routing evals.

## Harness tool inventory

Tool selections were checked with Claude Code 2.1.292 and Codex CLI 0.160.1 on 2026-10-07; app updates add and remove the app-managed entries, so read the tables as a snapshot.
The earlier version checks elsewhere in this document cover installer and instruction-loading
behavior, not this inventory. Installed files, enabled settings and connected servers are distinct:
`claude plugin list --json`, `claude mcp list`, `codex plugin list` and `codex mcp list --json`
report different parts of the setup. A plugin enable flag does not install missing dependencies or
establish authentication. These commands are read-only diagnostics; the MCP list may connect to
servers to check them. Tool availability does not widen the working agreement's Codex role.

### Claude Code

The user-scope registry holds the enabled marketplace plugins, covering the
[README's plugin checklist](../README.md#the-checklist). The settings template mirrors their
selection using the two fresh-install aliases described above. The three installed global LSP
plugins are disabled: `lua-lsp@claude-plugins-official`,
`rust-analyzer-lsp@claude-plugins-official` and `typescript-native-lsp@necturalabs`. Project/local
registrations, including C# LSP and the Unity plugin, are not global enablement decisions.
`cc-plugin-you-should-know@builtin` is separate from the marketplace installs.

| MCP source | Servers | Configuration |
|---|---|---|
| Enabled plugins | Blender, Cloudflare, GitHub, Godot, Meshy, Netlify, Sentry | Installed plugin manifests supply these servers; do not add second user-scope registrations. Netlify's platform plugin includes its `netlify` MCP server. |
| Disabled plugin MCP | Vercel | Keep `disabledMcpServers: ["plugin:vercel:vercel"]`; the Vercel plugin's skills stay enabled. A diagnostic listing a server does not override this setting. |
| User-scope servers | Scenario, Unity editor | Scenario uses `https://mcp.scenario.com/mcp`; follow `01.-getting-started:scenario` for authentication. Unity uses `claude mcp add -s user unity-editor-mcp -- unity mcp`. |
| Claude account connectors | Whatever your account connects on claude.ai | Managed on claude.ai, with account-specific connections and authentication. These are separate from plugin servers and are not restored by copying local JSON. |

If `claude plugin list` reports `dependencies-not-installed`, the enabled plugin is not fully
installed. For Vercel it recommends `claude plugin update vercel@claude-plugins-official` to fetch
the packages the plugin lists. Review that install separately; a setup sync only records the
selection and does not run it. Authentication status is also account-specific and is never
included in the public mirror.

The Claude app also syncs account-managed cached skills (document, browser and computer-use helpers among them). These are not AgentSkills marketplace entries, and cache presence alone is not proof that a skill loads in a particular CLI session. Reconnect through the app rather than copying account cache directories into this repository.

### Codex

The native plugin list reports the following installed and enabled selections. The versions are
observed versions, not repository-managed pins or promises about another account's catalog.

| Plugin | Source | Observed version |
|---|---|---|
| `browser` | `openai-bundled` | `26.924.22138` |
| `unified-computer-use` | `openai-bundled` | `26.924.22138` |
| `visualize` | `openai-bundled` | `1.0.41` |
| `openai-templates` | `openai-curated-remote` | `0.1.1` |
| `sites` | `openai-curated-remote` | `1.0.0-c` |
| `plugin-management` | `openai-curated-remote` | `0.1.0` |
| `work-pets` | `openai-curated-remote` | `0.1.6` |

The first three have enable flags in the user config; the four curated plugins are reported by
the native inventory without corresponding user-config tables. Preserve this app-managed state.
[OpenAI's plugin configuration documentation](https://developers.openai.com/plugins/build/plugins)
explains that user, project, cloud-managed and system configuration can supply plugin settings;
copying `config.toml` alone is not a complete backup of app or account tool selections.

The effective MCP inventory contains `node_repl` and `cua_repl`, both enabled and app-managed;
only `node_repl` appears in the user TOML. Their executable locations, environment and internal
connection wiring are deliberately not mirrored. The public template adds no MCP registrations
and does not reproduce Claude's Scenario, Unity, Meshy or Higgsfield connections in Codex.

Plugin skill files include visualization, Sites, plugin management, pet creation/management/
updates and artifact templates. The Codex system skill directory contains `imagegen`,
`openai-docs`, `review-agent`, `skill-creator` and `skill-installer`; which ones a session exposes
is decided by the harness. These stay supplied and updated by Codex or its app catalog. Do not
copy their implementations or plugin caches into AgentSkills. Configure catalog selections in
the app and verify the resulting native inventory on the target account.

## Optional development layout: link a checkout

```bash
git clone https://github.com/NecturaLabs/AgentSkills.git
cd AgentSkills
bash scripts/install.sh --dry-run
bash scripts/install.sh
bash scripts/doctor.sh
```

`install.sh` creates one symlink per skill into each harness's personal skill directory, for
whichever harnesses it finds. Editing the checkout changes what both harnesses load; there is no
copy step and nothing to keep in sync. `git pull` is the whole update procedure.

| Harness | Skill directory | Evidence |
|---|---|---|
| Claude Code | `~/.claude/skills/<name>/` | Documented; symlinked entries are followed and the skill is loaded once even when several locations point at the same target. Confirmed in a live session. |
| Codex | `~/.agents/skills/<name>/` | Verified on Codex CLI 0.155.1: `codex debug prompt-input`'s model-visible "### Skill roots" table lists `$HOME/.agents/skills` as a root, derived from `$HOME` and not relocated by a `CODEX_HOME` override; skills placed there, including as symlinks, are followed and appear under "Available skills". |

**`~/.agents/skills` is an active Codex user scan root, not merely an import/migration path.**
Verified on Codex CLI 0.155.1 with `codex debug prompt-input`: with `HOME=$SB` and no `CODEX_HOME`
override, skills in both `$SB/.codex/skills` and `$SB/.agents/skills` were both listed under
"Available skills"; with `HOME=$SB2` and `CODEX_HOME` pointed at an unrelated directory, the printed
root became `$SB2/.agents/skills` — so the root tracks `$HOME`, independent of `CODEX_HOME`. A
skill placed as a symlink inside `.agents/skills` was discovered and listed, and a repository-scoped
`<repo>/.agents/skills` is also an active root. (An empty root is simply omitted from the table.)
`$CODEX_HOME/skills` (default `~/.codex/skills`) remains a currently supported, older user root:
Codex's own bundled skills still live under `~/.codex/skills/.system/`, and its `skill-installer`
skill still documents only that path — the older convention lagging the newer public one, not
evidence the newer root is inactive. `install.sh` and `uninstall.sh` never write to
`$CODEX_HOME/skills`; `doctor.sh` inspects it so a shadowing skill name between the two roots is
visible.
Nothing is ever deleted from either root that this project did not create. Claude Code's user skill
root is unaffected by any of this — it stays `~/.claude/skills`. Verified on Claude Code 2.1.278:
`~/.agents/skills` and `.agents/skills` appear in the binary only inside its cross-agent import
scanner, alongside `~/.cursor/skills` and `.cursorrules`, so Claude Code treats that root as an
import source and never scans it for skills. The two harnesses therefore read disjoint roots and
one skill is never loaded twice.

### Safety

`install.sh` refuses to overwrite what it does not recognise. A real directory at a target path is
never replaced. A symlink pointing outside an AgentSkills checkout is never replaced. Both hold with
`--force`, which only ever repoints a link that already belongs to *some* AgentSkills checkout —
recognised by resolving the target and requiring both a `skills/` directory and a
`.claude-plugin/plugin.json` naming this plugin, so a lookalike path cannot masquerade.

`uninstall.sh` removes only symlinks whose name is one of this project's skills and whose target
resolves inside an AgentSkills checkout. It never removes a real directory, never removes a link
pointing elsewhere, and never removes the skill directories themselves. Anything it declines to
remove is printed with the reason.

Both take `--dry-run` and `--prefix <dir>`; `--prefix` overrides the home base, which is how the
scripts are tested without touching a real home directory.

## Optional: bootstrap the global working agreement

`install.sh` links skills and nothing else. Adopting a global operating policy changes how every
future session behaves, so it is a separate, explicit operation and is never implied:

```bash
bash scripts/install.sh --global-agents --dry-run
bash scripts/install.sh --global-agents [<file>]      # default: examples/global-agents.md
bash scripts/install.sh --global-agents <file> --replace-global
```

| Path | What it becomes | Why |
|---|---|---|
| `<prefix>/.agents/AGENTS.md` | Regular file, copied from the source | The canonical policy, in neither harness's directory. A copy rather than a symlink into the checkout, so `git pull` cannot silently rewrite it. |
| `<prefix>/.claude/CLAUDE.md` | Regular file containing exactly `@~/.agents/AGENTS.md` | Claude Code's `AGENTS.md` discovery walks the working directory's ancestors, so it never reaches a user-scope file; the import is what loads it. Verified on 2.1.278: a `CLAUDE.md` import resolves both `@~/…` and absolute paths. Delete this once native user-scope loading lands. |
| `<codex home>/AGENTS.md` | Symlink to the canonical file | Codex reads `$CODEX_HOME/AGENTS.md` through its own code path. Linking rather than copying is what keeps one maintained source instead of two that drift. |

**The policy lives in neither harness's directory.** Claude Code and Codex are peer consumers of
one neutral file, each reached through its own adapter, so adding a third harness later means
adding a third adapter rather than relocating the policy. There is no `~/.claude/AGENTS.md` in
this layout.

**The Codex adapter is the only symlink in this layout.** The canonical file and the Claude
adapter must both be regular files. A symlink at either is a conflict even when the bytes behind
it are exactly what would have been written, because the point of copying the canonical policy is
that nothing outside the user's own file decides what loads on every task — a link into a
checkout hands that back to the next `git pull`. `--replace-global` moves the symlink itself
aside as the backup and writes a regular file in its place.

Refusal rules, all of which hold with `--dry-run` and without it:

- **A run is all-or-nothing with respect to conflicts.** The three destinations are one
  mechanism, so every one is classified before anything is written. A canonical file that exists
  and differs is a conflict; so is a `CLAUDE.md` carrying anything beyond the import, a Codex
  `AGENTS.md` that is not already the link, and a symlink at the canonical path or the Claude
  adapter. "Just the import" is exact: a regular file whose one non-blank line is
  `@~/.agents/AGENTS.md` (a `--prefix` sandbox gets the absolute form, so the adapter points inside
  the sandbox rather than at the real home). Blank lines are fine; no other content is. `CLAUDE.md`
  is Markdown and has no comment syntax, so a `# note` line is a heading the model reads, and a second
  import such as `@OTHER.md` pulls in policy the canonical file does not control — either one
  makes the file a conflict.
  If any destination conflicts and `--replace-global` is absent, all conflicts are reported,
  **nothing is written anywhere**, and the run exits non-zero. Writing the adapters while
  refusing the canonical file would point both harnesses at a policy the run had just declined
  to install.
- `--replace-global` is the only way to replace any of them, and it moves the existing entry to
  `<path>.backup-<UTC timestamp>` first. One timestamp is fixed at the start of the run, so every
  backup path the run will need is known before the first write and all of them are checked for
  collisions up front. If any is already taken, every collision is reported and **nothing is
  written anywhere** — discovering one halfway through would leave the policy half installed, with
  the canonical file replaced and the adapter not, putting the two harnesses on different rules.
  An existing backup is never overwritten.
- `--replace-global` moves aside only a regular file or a symlink. A directory or any other
  special object at a destination is a hard conflict it cannot resolve: renaming one is not the
  same operation as replacing a file, and nothing here knows what it holds. Such a destination is
  reported and the run writes nothing, with or without the flag.
- `--replace-global` without `--global-agents` is rejected before anything is read or written.
- An `AGENTS.override.md` in the Codex home is reported, never removed — Codex prefers it over
  `AGENTS.md`, so it silently shadows the canonical policy.

`doctor.sh` reports the same surface read-only: whether a canonical policy exists at
`~/.agents/AGENTS.md` and is a regular file rather than a symlink, whether `CLAUDE.md` is a
regular file holding exactly the neutral import, whether the Codex file resolves to the canonical
one or has become a separate copy, and whether an override is shadowing it. It never repairs any
of them.

## Optional: Claude Code plugin, Codex linked to its marketplace clone

```
/plugin marketplace add NecturaLabs/AgentSkills
/plugin install necturalabs@necturalabs
```

```bash
cd ~/.claude/plugins/marketplaces/necturalabs
bash scripts/install.sh
bash scripts/doctor.sh
```

The plugin is copied into Claude Code's plugin cache, so a separate working checkout is not the
live source and its edits do not take effect. Plugin skills load namespaced, as
`necturalabs:<skill>`, so they can never displace a bundled skill.

**Skill names.** Codex lists a skill linked from a plugin checkout — any directory whose
`.claude-plugin/plugin.json` names a plugin — under that plugin's prefix. Verified on Codex CLI
0.156.1 with `codex debug prompt-input`: skills linked into `~/.agents/skills` from the marketplace
clone and, in a sandboxed `HOME`, from a plain working checkout were both listed as
`necturalabs:<skill>`. Claude Code lists personal skills in `~/.claude/skills` bare. So:

| Layout | Claude Code lists | Codex lists |
|---|---|---|
| Plugin in both harnesses | `necturalabs:<skill>` | `necturalabs:<skill>` |
| Plugin, Codex linked to its clone | `necturalabs:<skill>` | `necturalabs:<skill>` |
| Checkout linked into both | `<skill>` | `necturalabs:<skill>` |

A global policy that routes to these skills by name, as `examples/global-agents.md` does, names
each skill exactly once only under the plugin layout.

Codex installs the plugin from the same marketplace (`codex plugin marketplace add
NecturaLabs/AgentSkills`, then `codex plugin add necturalabs@necturalabs`); that remains a supported
optional layout introduced in 5.0.0. `install.sh` and `doctor.sh` recognise it from a `[plugins."necturalabs@…"]`
table with `enabled = true` in Codex's `config.toml`: install then puts no links into
`~/.agents/skills`, since Codex would load each skill twice, and doctor accepts the plugin and warns
about any link that duplicates it.

`install.sh` and `doctor.sh` recognise the Claude Code plugin from `installed_plugins.json`,
counting it only while `enabledPlugins` marks it true. With it enabled, `install.sh` puts no links
into `~/.claude/skills` — a personal link beside the plugin would load every skill twice — and
still links Codex; `doctor.sh` accepts the plugin as the Claude install and warns about any
personal link that duplicates it. Run from the marketplace clone, `install.sh` links Codex to the
same copy Claude Code installed from, and the links follow `claude plugin marketplace update`;
`claude plugin update necturalabs@necturalabs` then refreshes Claude Code's cached copy. `doctor.sh`
accepts Codex links into that clone from whichever checkout it runs, and still reports a link into
any other checkout as an error.

## Any other harness

The skills follow the open Agent Skills specification and their frontmatter is restricted to the six
spec keys, so any conforming harness can load them. Point it at `skills/<name>/`. Claude Code and
Codex are the two that are tested here.

## Native skill names

A skill that shares a name with a harness's own capability displaces or shadows it. In Claude Code a personal
or project skill replaces a bundled skill of the same name — but not its aliases, so `/review`
would still reach the bundled `/code-review` — while plugin skills are namespaced `plugin:name` and
never collide. Codex lists two same-named skills side by side with no precedence. No skill here
reuses a native name: the validator checks every name against `scripts/native-names.tsv`, and
`doctor.sh` reports a collision on the installed checkout, reading Codex's system skills live from
`$CODEX_HOME/skills/.system` and checking Claude Code against the list. Claude Code keeps its bundled
skills inside the binary, materialized lazily, so no directory lists them and the list is maintained
by hand; `doctor.sh` notes when the installed version is newer than the one it was verified on.

Either harness can switch off a native skill you do not want. Claude Code: `skillOverrides` in
`settings.json` (`{"skillOverrides": {"<name>": "off"}}`), or `disableBundledSkills: true` for all of
them. Codex: a `[[skills.config]]` entry in `config.toml` with the skill's `path` and
`enabled = false` — verified on 0.155.1 to hide system skills as well — confirmed with
`codex debug prompt-input`, which prints the skill list the model sees.

## Instruction files

The skills are independent of how your `AGENTS.md` is loaded, but the two interact often enough to
be worth stating.

**Claude Code 2.1.278** discovers `AGENTS.md` and `.claude/AGENTS.md` by walking the ancestors of the
working directory. By default it reads them only when no `CLAUDE.md`, `.claude/CLAUDE.md` or
`CLAUDE.local.md` exists at or above that directory — so removing a project's `CLAUDE.md` is what
switches that repository to native `AGENTS.md` loading. The behavior is governed by the
`instructionFiles` setting: `claude-md`, `claude-md-or-agents-md` (default), `claude-md-and-agents-md`,
`managed-only`. Availability is additionally gated by a remote feature flag whose built-in default is
off, so another account may not have it.

One consequence is easy to miss: **a user-scope `AGENTS.md` is not reached by an ancestors walk**
from a project stored elsewhere on disk, so it is not loaded natively wherever you keep it.
Verified by moving `~/.claude/CLAUDE.md` aside and starting a fresh session: the global
instructions did not load. A `~/.claude/CLAUDE.md` holding a single import is what loads user-scope
policy, and the import may name any path — verified on 2.1.278 that both `@~/…` and an absolute
path resolve, against a file reachable only through the import. That is why the bootstrap above
can keep the policy at `~/.agents/AGENTS.md` and still have Claude Code load it.

**Codex 0.155.1** reads `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) through its own code
path, and separately discovers project-level `AGENTS.override.md`, then `AGENTS.md`, then any
configured fallback filenames by walking up from the working directory. `project_doc_max_bytes`
(default 32768) is consumed cumulatively across the documents found in that walk only, and one that
would push the running total past the budget is truncated with no message the user sees. The global
file is loaded through a separate path and does not consume that budget, so its size does not reduce
what projects may load.

`doctor.sh` reports all of this: which instruction files exist, the `instructionFiles` setting, where
`~/.codex/AGENTS.md` points if it is a symlink, and the resolved global file's size against the
budget actually configured on this machine.

## Filesystem notes

Symlinks into a checkout on another mount work normally; it is an ordinary VFS operation and neither
harness inspects the filesystem type. Two caveats seen on an NTFS (`ntfs3`) mount: every file reports
mode `0755` regardless of its real permissions, so a skill relying on a meaningful executable bit
will not get one; and lookups were case-sensitive, matching Linux behavior. Neither affects
Markdown-only skills.
