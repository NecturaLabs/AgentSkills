# Migration: v2 to v3

v3 changes how these skills relate to what each harness already ships. Both Claude Code and Codex
now have maintained review capabilities of their own, and v2 both collided with one of them by name
and shipped a global policy that routed around them.

## What changed and why

**Two skills were renamed off native names.**

| v2 | v3 | Why |
|---|---|---|
| `change-review` | `independent-review` | The name read as the generic code-review slot, which is how a global routing table came to mandate it over the harness's own reviewer. The new name states what it adds: independence, evidence, adjudication and a stop rule. |
| `security-review` | `threat-review` | Claude Code bundles a skill named `security-review`. Installed into `~/.claude/skills`, v2's replaced Anthropic's `/security-review` — but not its aliases — while the plugin install, being namespaced, did not, so the two install paths behaved differently. The new name states what it does: triage by threat surface. |

**The review skills are native-first procedures.** `independent-review` uses the harness's own
review command as its review pass when that command runs in a separate context, and keeps scope,
briefing, adjudication and stopping. `threat-review` defers to a native security review for what it
covers and keeps what it excludes — Claude Code's reports only high-confidence findings and excludes
denial of service, resource exhaustion and outdated dependencies.

**`agent-orchestration` was added.** The delegation procedure that made up about a third of the
global example moved into a skill that loads only when work is split across agents.

**The global example is durable policy only.** 27 KB and 433 lines became about 10 KB and 162
lines. The routing table became a Capabilities section that routes by requirement and prefers a
native capability where it fits; procedure that was repeated from the skills was removed from it.

**Native names are enforced.** `scripts/native-names.tsv` lists the names each harness already owns,
the validator fails on a skill that reuses one, and `doctor.sh` reports a collision on the installed
checkout.

## Upgrading

Symlink install:

```bash
git pull
bash scripts/install.sh --dry-run   # shows the old-name links it will retire
bash scripts/install.sh
bash scripts/doctor.sh
```

`install.sh` retires a link under an old name only when it provably belongs to an AgentSkills
checkout; see `docs/installation.md`. Plugin install: update the marketplace and the plugin, and the
skills appear under their new names.

Your own instruction files are never rewritten. Search them for `change-review` and
`security-review` and update each reference. If a routing rule names this plugin's skill as the only
acceptable route for review — the v2 example's did — rewrite it as a requirement that the harness's
own review command or `independent-review` can satisfy; the v3 example's Capabilities and Review
sections show the shape. `install.sh --global-agents --replace-global` installs the v3 example
itself, backing up the file it replaces.
