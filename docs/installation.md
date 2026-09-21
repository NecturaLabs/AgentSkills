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
evidence the newer root is inactive. `install.sh` no longer writes to `$CODEX_HOME/skills`;
`doctor.sh` inspects it so a duplicate or shadowing skill name between the two roots is visible.
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
remove is printed with the reason. `--include-legacy` extends it to v1 skill names.

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
  and differs is a conflict; so is a `CLAUDE.md` carrying anything beyond the import, and a Codex
  `AGENTS.md` that is not already the link, a symlink at the canonical path or the Claude
  adapter, and a policy still sitting at the pre-release `<prefix>/.claude/AGENTS.md`. "Just the
  import" is exact: a regular file whose one non-blank line is `@~/.agents/AGENTS.md`
  (a `--prefix` sandbox gets the absolute form, so the adapter points inside the sandbox rather
  than at the real home). Blank lines are
  fine; no other content is. `CLAUDE.md` is Markdown
  and has no comment syntax, so a `# note` line is a heading the model reads, and a second
  import such as `@OTHER.md` pulls in policy the canonical file does not control — either one
  makes the file a conflict.
  If any destination conflicts and `--replace-global` is absent, all conflicts are reported,
  **nothing is written anywhere**, and the run exits non-zero. Writing the adapters while
  refusing the canonical file would point both harnesses at a policy the run had just declined
  to install.
- `--replace-global` is the only way to replace any of them, and it moves the existing file to
  `<path>.backup-<UTC timestamp>` first. It never overwrites an existing backup; if one from the
  same second is already there, that action is abandoned and the original is left alone.
- `--replace-global` without `--global-agents` is rejected before anything is read or written.
- An `AGENTS.override.md` in the Codex home is reported, never removed — Codex prefers it over
  `AGENTS.md`, so it silently shadows the canonical policy.

### Migrating the pre-release layout

An earlier revision of this branch put the policy at `~/.claude/AGENTS.md`, with the adapter
importing `@AGENTS.md` and Codex linked into Claude's directory. That layout was never released
and is not a compatibility contract. It is recognized, never silently changed:

- `doctor.sh` reports a policy still at `~/.claude/AGENTS.md` as the pre-release canonical path
  and names the migration command; it reports an adapter importing `@AGENTS.md` as pointing back
  into Claude's own directory; and it reports a Codex adapter still aimed at the old path.
- An ordinary `--global-agents` run treats the old policy as a conflict, so it refuses and writes
  nothing rather than leaving two files that both claim to be the policy.
- `install.sh --global-agents --replace-global` migrates it: the old file's own bytes become the
  source when no `FILE` was named, so the policy moves rather than being overwritten by the
  example; the adapter is rewritten to the neutral import; Codex is relinked; and the old file is
  moved to a timestamped backup rather than deleted. Naming a `FILE` explicitly still wins, and
  the old policy is backed up either way.
- If an old `~/.claude/AGENTS.md` is still present after a run that did not migrate, `doctor.sh`
  reports it as leftover state that is no longer read as policy — it never deletes it.

`doctor.sh` reports the same surface read-only: whether a canonical policy exists at
`~/.agents/AGENTS.md` and is a regular file rather than a symlink, whether `CLAUDE.md` is a
regular file holding exactly the neutral import, whether the Codex file resolves to the canonical
one or has become a separate copy, and whether an override is shadowing it. It never repairs any
of them.

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
