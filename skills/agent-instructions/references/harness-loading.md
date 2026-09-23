# Harness loading facts

Where an instruction file lives decides whether it loads at all, and how much of it survives
decides whether the back half of a long file is ever seen. Both failures are silent — no error, no
warning, just guidance that was never read. This reference states what is empirically verified on
this machine (Claude Code 2.1.278 and 2.1.280, Codex 0.155.1) separately from what is inferred, so a claim here
can be traced back to which kind of evidence backs it. Verify against the harness's own docs and,
where possible, its own diagnostic output before relying on a fact here for a version this wasn't
checked against.

## Claude Code (2.1.278) — verified

- Discovers `AGENTS.md` and `.claude/AGENTS.md` by walking **ancestors of the working directory** —
  project-root discovery, not a fixed location.
- By default it reads those files only when **no** `CLAUDE.md`, `.claude/CLAUDE.md` or
  `CLAUDE.local.md` exists at or above the working directory. Any of those three present switches
  the repository back to `CLAUDE.md`-only loading.
- The behavior is governed by the settings key `instructionFiles` (nested under
  `pluginConfigs["agents-md@builtin"].options` in the settings schema), with values:
  - `claude-md` — `CLAUDE.md` only, `AGENTS.md` never read
  - `claude-md-or-agents-md` — the default described above
  - `claude-md-and-agents-md` — both, always
  - `managed-only` — only an organization-managed file
- **Consequence:** a user-scope `AGENTS.md` is **not** reached by an ancestors walk from a project
  rooted elsewhere on disk — the walk starts at the working directory and climbs, it does not also
  check the home directory. Nothing loads it natively, wherever you keep it. A `~/.claude/CLAUDE.md`
  holding a single import is what actually loads it, because `CLAUDE.md`'s own import mechanism —
  not the `AGENTS.md` discovery path — pulls the file in.
- **Verified:** that import may name any path, not just a sibling. Both `@~/…` and an absolute path
  resolve, checked on 2.1.278 against a file reachable only through the import. So the user-scope
  policy does not have to live in the harness's own directory; the adapter can point anywhere.
- Support for native `AGENTS.md` reading is additionally gated by a remote feature flag whose
  code-level default is off. It can be unavailable on another account even at the same client
  version, independent of the `instructionFiles` setting.

## Codex (0.155.1)

- **Verified:** reads `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) through one code path,
  and separately discovers project-level `AGENTS.override.md`, then `AGENTS.md`, then any
  configured fallback filenames, walking **up** from the working directory to the project root.
- **Verified:** `project_doc_max_bytes` (default **32768**, i.e. 32 KiB) is a single cumulative
  budget consumed across every **project-level** document found in that upward walk. Once the
  running total would exceed the budget, the document that would cross it is truncated — silently,
  with no error surfaced to the user. Because the walk concatenates root-first, what gets cut is
  whichever file is deepest, meaning the most specific file, the one closest to the work actually
  being done.
- **Verified:** the global `$CODEX_HOME/AGENTS.md` is read through its own code path and does *not*
  draw on `project_doc_max_bytes`. Its size therefore cannot starve a project of its own
  instructions. Re-check this against the installed version before relying on it, since it is a
  property of the implementation rather than of a documented contract.

## Skills: precedence and name collisions

Routing entries and skill names interact with what each harness already ships. Verified on Claude
Code 2.1.280 and Codex 0.155.1.

- **Claude Code** loads skills from managed, personal (`~/.claude/skills`), project
  (`.claude/skills`, including nested and ancestor directories) and plugin locations, plus the
  skills bundled into the binary. Same-name precedence is managed, then personal, then project, and
  any of those **replaces a bundled skill of the same name but not its aliases** — a personal
  `code-review` replaces `/code-review` while the bundled alias `/review` still runs the bundled
  one. Plugin skills are namespaced `plugin:name`, so they never collide with anything.
  `skillOverrides` in settings hides or disables one skill by name (`"off"`, `"name-only"`,
  `"user-invocable-only"`; plugin skills excepted) and `disableBundledSkills` removes every bundled
  one. Bundled skills live inside the binary and are materialized lazily, so no directory lists
  them all; `/skills` or `/context` in a session shows each skill's source.
- **Codex** scans repository `.agents/skills` directories up to the root, `~/.agents/skills`,
  `$CODEX_HOME/skills`, `/etc/codex/skills`, plugin caches, and its system skills under
  `$CODEX_HOME/skills/.system`. Two skills with the same name are **not merged — both are listed**,
  with no precedence, so a collision leaves the model choosing between them. A skill linked from a
  directory inside a plugin checkout is listed under that plugin's `name:` prefix. A
  `[[skills.config]]` entry in `config.toml` with the skill's `path` and `enabled = false` disables
  one, system skills included; `codex debug prompt-input` prints the skill roots and the list the
  model actually sees.
- **Names differ by install, verified on Claude Code 2.1.281 and Codex 0.156.1.** A plugin skill is
  `plugin:name` in Claude Code; a personal skill in `~/.claude/skills` is bare. Codex lists a skill
  linked from any plugin checkout — a directory whose `.claude-plugin/plugin.json` names a plugin
  — under that prefix, from `~/.agents/skills` too. A routing entry must spell the skill as the
  harness lists it, so one entry serves both harnesses only when both list the same name.

The consequence for instruction files: never give a custom skill a native capability's name unless
replacing that capability is the whole point, and never write a routing rule that forces a custom
skill over a native one. Name what the skill adds instead, and state the requirement so either can
meet it.

## The practical rule

The budget binds the project chain, not the global file. Size each accordingly: a global file is
constrained by the attention it costs on every task, a project chain by a cap that truncates it. A
file that is silently truncated is indistinguishable, from the agent's behavior, from one whose
rules it chose to ignore — which is why the project chain is where size discipline actually
matters.

The same reasoning applies one level down: in a monorepo, a chain of nested `AGENTS.md` files
concatenated root-to-leaf can hit the same cap. Keep every file in a nested chain short, not only
the root, and measure the chain's cumulative size — root through the deepest file in scope —
before assuming a deep chain of them costs nothing.

## Confirming what actually loaded

Do not ask a model to summarize its own instructions and treat that as verification — a model can
omit a truncated or unloaded file from its summary without saying so. Prefer the harness's own
record of what it resolved:

- **Claude Code** lists the memory files it loaded for the current session, and where each one came
  from, in its own context/status output.
- **Codex** prints the model-visible input with `codex debug prompt-input`, run from the working
  directory in question: its `AGENTS.md instructions` block is the chain as actually concatenated,
  and its skill list is what the model can load. Verified on 0.156.1.

Where neither is available, a prompted check ("summarize your current instructions") is a weaker
fallback — it reflects the model's account, not the loader's, and a silently dropped file will not
necessarily show up as a gap in the summary. Never disable approval prompts or sandboxing just to
run a diagnostic read.

After creating or editing an instruction file — root or nested — confirm it loads before reporting
the work done. A chain that silently exceeded a byte cap looks identical, from the outside, to one
that loaded cleanly, and that is exactly the failure a model's own summary is least able to catch.
