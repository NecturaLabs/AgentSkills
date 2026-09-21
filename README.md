# AgentSkills

Five Agent Skills for coding agents: instruction-file maintenance, independent code review, security
review, test engineering, and project documentation.

They follow the open [Agent Skills specification](https://agentskills.io/specification), so one
checkout serves every conforming harness. Claude Code and OpenAI Codex are the two that are tested.

## Architecture

Four layers, each holding one kind of knowledge:

```
AGENTS.md              persistent policy and routing   — paid for on every task
skills/*/SKILL.md      conditional procedure           — paid for when the trigger matches
   references/         detail                          — paid for when the mode needs it
docs/, code, config    project truth                   — read when relevant
scripts/, tests/, CI   deterministic enforcement       — no model call at all
```

The point is that strong behavior should be cheap. A rule that must be in context on every task is
expensive and has to earn it; a procedure that matters on one task in twenty belongs in a skill that
loads on demand; anything a script can decide should never reach a model at all.

`AGENTS.md` is the only maintained policy source — no competing CLAUDE policy layer, no context
loader, no session-start hook that reinjects text. A second always-loaded file doesn't add guidance,
it adds a copy that drifts. A repository `CLAUDE.md` is forbidden here and the validator fails the
build if one reappears; the one verified exception is a user-scope shim outside this repo, covered
in [docs/installation.md](docs/installation.md).

See [docs/architecture.md](docs/architecture.md) for the full reasoning and
[docs/skill-design.md](docs/skill-design.md) for how to decide where a given piece of knowledge
belongs.

## Skills

| Skill | Use when |
|---|---|
| **`agent-instructions`** | Writing a repository's `AGENTS.md`, auditing one for stale or oversized guidance, or deciding what belongs in persistent instructions versus a skill, a document or a lint rule |
| **`change-review`** | A behavioral, cross-file, schema, dependency or concurrency change is finished and needs a reviewer that did not write it |
| **`security-review`** | A change touches authentication, authorization, sessions, tokens, cryptography, secrets, external input, deserialization, file or network boundaries, permissions, or dependencies |
| **`testing`** | Adding coverage for new behavior, writing a regression test for a defect, fixing a failing or flaky test, choosing the right test level, or auditing a suite |
| **`project-docs`** | Recording a consequential decision and its rationale, documenting how a system is structured, or auditing docs that have drifted from the code |

Each description states what the skill is *not* for as well, because that clause is what keeps
neighbouring skills from firing on each other's work.

## Install

Linking the checkout is the recommended setup: it keeps one editable canonical source, and both
harnesses follow symlinked skill directories.

```bash
git clone https://github.com/NecturaLabs/AgentSkills.git
cd AgentSkills
bash scripts/install.sh --dry-run    # preview every action
bash scripts/install.sh
```

This creates one symlink per skill in `~/.claude/skills/` (Claude Code) and `~/.agents/skills/`
(Codex), for whichever harnesses are present. `$CODEX_HOME/skills` (default `~/.codex/skills`) is an
older, still-supported Codex root that install no longer writes to; `doctor.sh` checks it so a
shadowing duplicate is visible. Install refuses to overwrite anything it doesn't recognise: a real
directory is never replaced, and a symlink pointing outside an AgentSkills checkout is never
replaced, `--force` included.

Claude Code users who prefer the plugin mechanism can install from the marketplace instead:

```
/plugin marketplace add NecturaLabs/AgentSkills
/plugin install necturalabs@necturalabs
```

### Update, check, remove

```bash
git pull                                 # the links follow the checkout
bash scripts/doctor.sh                   # what is installed, what is broken, what conflicts
bash scripts/uninstall.sh                # removes only links this project created
bash scripts/uninstall.sh --include-legacy   # also removes v1 skill links
```

`doctor.sh` also reports instruction-file health — whether a `CLAUDE.md` is suppressing native
`AGENTS.md` loading, and how your project instruction files measure against Codex's
`project_doc_max_bytes` budget (32 KiB by default). That budget covers the project-level documents
Codex finds walking up from the working directory; a document exceeding the running total is
truncated **silently**, which is indistinguishable from a rule the agent chose to ignore. The global
`~/.codex/AGENTS.md` loads separately and does not consume it.

## Validate

```bash
npm test                          # the full offline suite
bash scripts/validate.sh --strict # structure validation only
```

The suite is entirely offline — every check reads files in this repository. Nothing needs the
network, credentials, or the `claude` CLI, and nothing that does may be added: no API key belongs in
this repo or its CI, so such a check could only ever be skipped, and a permanently skipped check
reads as coverage while providing none.

Two official tools complement it, for humans rather than CI:

```bash
claude plugin validate . --strict   # Anthropic's manifest and frontmatter validator
claude plugin eval .                # routing evals — spends tokens, needs credentials
```

Each skill ships five routing eval cases under `evals/`: explicit, implicit, contextual, negative and
ambiguous. The negative cases are the valuable ones — they catch a description broad enough to fire
on a neighbour's work. CI validates that the case files exist and parse; it never executes them.

## Compatibility

`SKILL.md` frontmatter carries only the six keys the spec defines — `name`, `description`, `license`,
`compatibility`, `metadata`, `allowed-tools`. Claude-Code-only keys such as `when_to_use`, `model` or
`context` are rejected outright by the Skills API and undocumented for Codex, so the validator fails
on them. Skill bodies are written harness-neutral: they name capabilities, not one product's tool
names.

Semver across `package.json` and `.claude-plugin/plugin.json`: patch for fixes, minor for new skills
or features, major for removed skills or a restructured layout.

Upgrading from v1? See [docs/migration-v1-to-v2.md](docs/migration-v1-to-v2.md). Thirteen skills
became five, the session-start hook is gone, and the external plugin dependency is gone.

## License

MIT. See [LICENSE](LICENSE).
