# Installation

Verified against Claude Code 2.1.278 and Codex CLI 0.155.1 on Linux. Where a claim below was not
confirmed by running it, that is stated.

## Recommended: link the checkout

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
| Codex | `~/.codex/skills/<name>/` (`$CODEX_HOME/skills`) | Codex's own bundled skills live in `~/.codex/skills/.system/`, and its `skill-installer` skill documents installing into `$CODEX_HOME/skills`. |

**`~/.agents/skills` is not a scan path.** It appears in both products only as an import/migration
source — Claude Code's `claude import` and Codex's `external-agent-migration`. A skill linked only
there is loaded by neither. `doctor.sh` reports anything found there so an older install is visible,
and never requires it.

### Safety

`install.sh` refuses to overwrite what it does not recognise. A real directory at a target path is
never replaced. A symlink pointing outside an AgentSkills checkout is never replaced. Both hold with
`--force`, which only ever repoints a link that already belongs to *some* AgentSkills checkout —
recognised by resolving the target and requiring both a `skills/` directory and a
`.claude-plugin/plugin.json` naming this plugin, so a lookalike path cannot masquerade.

`uninstall.sh` removes only symlinks whose name is one of this project's skills and whose target
resolves inside an AgentSkills checkout. It never removes a real directory, never removes a link
pointing elsewhere, and never removes the skill directories themselves. Anything it declines to
remove is printed with the reason. `--include-legacy` extends it to v1 skill names.

Both take `--dry-run` and `--prefix <dir>`; `--prefix` overrides the home base, which is how the
scripts are tested without touching a real home directory.

## Alternative: Claude Code plugin

```
/plugin marketplace add NecturaLabs/AgentSkills
/plugin install necturalabs@necturalabs
```

This copies the plugin into Claude Code's plugin cache, so the checkout is no longer the live source
and local edits do not take effect. Use it if you only want Claude Code and do not intend to modify
the skills. Do not combine it with the symlink install — `doctor.sh` reports the duplicate skill
names that would shadow each other.

## Any other harness

The skills follow the open Agent Skills specification and their frontmatter is restricted to the six
spec keys, so any conforming harness can load them. Point it at `skills/<name>/`. Claude Code and
Codex are the two that are tested here.

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

One consequence is easy to miss: **a user-scope `~/.claude/AGENTS.md` is not reached by an ancestors
walk** from a project stored elsewhere on disk, so it is not loaded natively. Verified by moving
`~/.claude/CLAUDE.md` aside and starting a fresh session: the global instructions did not load. If
you keep global policy in `~/.claude/AGENTS.md`, a `~/.claude/CLAUDE.md` containing only
`@AGENTS.md` is what loads it.

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
